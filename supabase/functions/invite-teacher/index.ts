import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { class_id, email } = await req.json();
    if (!class_id || !email) {
      return new Response(JSON.stringify({ error: "class_id와 email이 필요합니다" }), { status: 400, headers: corsHeaders });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "인증 정보가 없습니다" }), { status: 401, headers: corsHeaders });
    }

    const callerClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: isOwner, error: ownerErr } = await callerClient.rpc("is_class_owner", { p_class_id: class_id });
    if (ownerErr || !isOwner) {
      return new Response(JSON.stringify({ error: "이 반의 원장만 교사를 초대할 수 있습니다" }), { status: 403, headers: corsHeaders });
    }

    const { data: userData } = await callerClient.auth.getUser();

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { error: inviteErr } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { invited_class_id: class_id },
      redirectTo: `${Deno.env.get("SITE_URL")}/teacher-onboarding.html`,
    });

    if (inviteErr) {
      return new Response(JSON.stringify({ error: inviteErr.message }), { status: 400, headers: corsHeaders });
    }

    const { data: existing } = await adminClient
      .from("teacher_invites")
      .select("id")
      .eq("class_id", class_id)
      .eq("email", email)
      .eq("status", "pending")
      .maybeSingle();

    let recordErr;
    if (existing) {
      const { error } = await adminClient
        .from("teacher_invites")
        .update({ invited_at: new Date().toISOString(), invited_by: userData.user?.id })
        .eq("id", existing.id);
      recordErr = error;
    } else {
      const { error } = await adminClient
        .from("teacher_invites")
        .insert({ class_id, email, invited_by: userData.user?.id, status: "pending" });
      recordErr = error;
    }

    if (recordErr) {
      return new Response(JSON.stringify({ error: recordErr.message }), { status: 500, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ success: true }), { status: 200, headers: corsHeaders });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
});
