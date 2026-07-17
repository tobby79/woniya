import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type PreparedInvite = {
  invite_id: string;
  normalized_email: string;
  delivery_attempt_id: string;
  reused: boolean;
  dispatch_action: "send" | "in_progress" | "already_sent";
  retry_after_seconds: number;
};

type DeliveryResult = {
  updated: boolean;
  finalized: boolean;
  result_code:
    | "applied"
    | "already_applied"
    | "stale_attempt"
    | "invite_not_pending"
    | "finalize_conflict"
    | "invite_not_found";
  delivery_status: "not_sent" | "sending" | "sent" | "failed" | null;
};

type DeliveryErrorCode = "auth_invite_failed" | "auth_user_already_exists";

type FinalizeOutcome =
  | { kind: "success"; result: DeliveryResult }
  | { kind: "terminal"; result: DeliveryResult }
  | { kind: "uncertain" };

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isPreparedInvite(value: unknown): value is PreparedInvite {
  return isRecord(value) &&
    typeof value.invite_id === "string" &&
    typeof value.normalized_email === "string" &&
    typeof value.delivery_attempt_id === "string" &&
    typeof value.reused === "boolean" &&
    (value.dispatch_action === "send" ||
      value.dispatch_action === "in_progress" ||
      value.dispatch_action === "already_sent") &&
    typeof value.retry_after_seconds === "number" &&
    Number.isInteger(value.retry_after_seconds) &&
    value.retry_after_seconds >= 0;
}

function isDeliveryResult(value: unknown): value is DeliveryResult {
  if (!isRecord(value)) return false;

  const resultCodes = [
    "applied",
    "already_applied",
    "stale_attempt",
    "invite_not_pending",
    "finalize_conflict",
    "invite_not_found",
  ];
  const deliveryStatuses = ["not_sent", "sending", "sent", "failed", null];

  return typeof value.updated === "boolean" &&
    typeof value.finalized === "boolean" &&
    typeof value.result_code === "string" &&
    resultCodes.includes(value.result_code) &&
    deliveryStatuses.includes(value.delivery_status as string | null);
}

function errorField(error: unknown, field: "code" | "message"): string {
  if (!isRecord(error) || typeof error[field] !== "string") return "";
  return error[field].toLowerCase();
}

function mapAuthInviteError(error: unknown): DeliveryErrorCode {
  const code = errorField(error, "code");
  const message = errorField(error, "message");

  if (
    code === "email_exists" ||
    code === "user_already_exists" ||
    message.includes("already been registered") ||
    message.includes("already registered") ||
    message.includes("user already exists")
  ) {
    return "auth_user_already_exists";
  }

  return "auth_invite_failed";
}

function isRetryableFinalizeRpcError(error: unknown): boolean {
  const code = errorField(error, "code");
  return code === "" || [
    "40001",
    "40p01",
    "55p03",
    "57014",
    "pgrst000",
    "pgrst001",
    "pgrst002",
    "pgrst003",
  ].includes(code);
}

function prepareErrorResponse(error: unknown) {
  const message = errorField(error, "message");

  if (message.includes("not_authenticated")) {
    return jsonResponse(401, { success: false, error: "unauthorized" });
  }
  if (message.includes("class_access_denied")) {
    return jsonResponse(403, { success: false, error: "forbidden" });
  }
  if (message.includes("class_already_assigned")) {
    return jsonResponse(409, { success: false, error: "class_already_assigned" });
  }
  if (message.includes("class_id_required") || message.includes("email_invalid")) {
    return jsonResponse(400, { success: false, error: "invalid_request" });
  }

  return jsonResponse(500, { success: false, error: "invite_prepare_failed" });
}

function logFinalizeFailure(
  inviteId: string,
  deliveryAttemptId: string,
  errorCode: string,
) {
  console.error(JSON.stringify({
    event: "teacher_invite_delivery_finalize_failed",
    invite_id: inviteId,
    delivery_attempt_id: deliveryAttemptId,
    error_code: errorCode,
  }));
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { success: false, error: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const siteUrl = Deno.env.get("SITE_URL");

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !siteUrl) {
      return jsonResponse(500, { success: false, error: "server_config_error" });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return jsonResponse(401, { success: false, error: "unauthorized" });
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { success: false, error: "invalid_request" });
    }

    if (!isRecord(body)) {
      return jsonResponse(400, { success: false, error: "invalid_request" });
    }

    const classId = body.class_id;
    const email = body.email;
    if (
      typeof classId !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(classId) ||
      typeof email !== "string" ||
      email.length > 320 ||
      email.trim() === ""
    ) {
      return jsonResponse(400, { success: false, error: "invalid_request" });
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: callerData, error: callerError } = await callerClient.auth.getUser();
    if (callerError || !callerData.user) {
      return jsonResponse(401, { success: false, error: "unauthorized" });
    }

    const { data: preparedData, error: prepareError } = await callerClient.rpc(
      "prepare_teacher_invite_delivery",
      { p_class_id: classId, p_email: email },
    );

    if (prepareError) {
      return prepareErrorResponse(prepareError);
    }
    if (!isPreparedInvite(preparedData)) {
      return jsonResponse(500, { success: false, error: "invite_prepare_failed" });
    }

    if (preparedData.dispatch_action === "in_progress") {
      return jsonResponse(200, {
        success: true,
        invite_id: preparedData.invite_id,
        reused: preparedData.reused,
        dispatch_action: preparedData.dispatch_action,
        delivery_status: "sending",
        retry_after_seconds: preparedData.retry_after_seconds,
        message: "초대 메일 발송이 진행 중입니다.",
      });
    }

    if (preparedData.dispatch_action === "already_sent") {
      return jsonResponse(200, {
        success: true,
        invite_id: preparedData.invite_id,
        reused: preparedData.reused,
        dispatch_action: preparedData.dispatch_action,
        delivery_status: "sent",
        retry_after_seconds: preparedData.retry_after_seconds,
        message: "최근 초대 메일이 이미 발송되었습니다.",
      });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const finalizeDelivery = async (
      succeeded: boolean,
      errorCode: DeliveryErrorCode | null,
    ): Promise<FinalizeOutcome> => {
      const retryDelays = [200, 600];

      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const { data, error } = await adminClient.rpc(
            "finalize_teacher_invite_delivery",
            {
              p_invite_id: preparedData.invite_id,
              p_delivery_attempt_id: preparedData.delivery_attempt_id,
              p_succeeded: succeeded,
              p_error_code: errorCode,
            },
          );

          if (!error && isDeliveryResult(data)) {
            if (data.result_code === "applied" || data.result_code === "already_applied") {
              return data.finalized
                ? { kind: "success", result: data }
                : { kind: "uncertain" };
            }

            return { kind: "terminal", result: data };
          }

          if (!error || !isRetryableFinalizeRpcError(error)) {
            return { kind: "uncertain" };
          }
        } catch {
          // Retry only the delivery result write; never repeat the Auth call.
        }

        if (attempt < retryDelays.length) {
          await wait(retryDelays[attempt]);
        }
      }

      return { kind: "uncertain" };
    };

    const { error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
      preparedData.normalized_email,
      {
        data: { invited_class_id: classId },
        redirectTo: `${siteUrl.replace(/\/$/, "")}/teacher-onboarding.html`,
      },
    );

    const deliveryErrorCode = inviteError ? mapAuthInviteError(inviteError) : null;
    const finalizeOutcome = await finalizeDelivery(!inviteError, deliveryErrorCode);

    if (finalizeOutcome.kind === "uncertain") {
      logFinalizeFailure(
        preparedData.invite_id,
        preparedData.delivery_attempt_id,
        "delivery_finalize_uncertain",
      );
      return jsonResponse(500, { success: false, error: "delivery_finalize_uncertain" });
    }

    if (finalizeOutcome.kind === "terminal") {
      const resultCode = finalizeOutcome.result.result_code;
      const errorCode = resultCode === "stale_attempt"
        ? "delivery_finalize_stale"
        : resultCode === "invite_not_pending"
        ? "delivery_finalize_invite_not_pending"
        : resultCode === "finalize_conflict"
        ? "delivery_finalize_conflict"
        : "delivery_finalize_invite_not_found";

      logFinalizeFailure(
        preparedData.invite_id,
        preparedData.delivery_attempt_id,
        errorCode,
      );
      return jsonResponse(resultCode === "invite_not_found" ? 500 : 409, {
        success: false,
        error: errorCode,
      });
    }

    if (inviteError && deliveryErrorCode) {
      return jsonResponse(deliveryErrorCode === "auth_user_already_exists" ? 409 : 502, {
        success: false,
        error: deliveryErrorCode,
      });
    }

    return jsonResponse(200, {
      success: true,
      invite_id: preparedData.invite_id,
      reused: preparedData.reused,
      dispatch_action: preparedData.dispatch_action,
      delivery_status: "sent",
      retry_after_seconds: preparedData.retry_after_seconds,
    });
  } catch {
    return jsonResponse(500, { success: false, error: "internal_error" });
  }
});
