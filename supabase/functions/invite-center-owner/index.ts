import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPER_ADMIN_EMAIL = "tobby79@naver.com";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { center_id, email } = await req.json();
    if (!center_id || !email) {
      return new Response(JSON.stringify({ error: "center_id와 email이 필요합니다" }), { status: 400, headers: corsHeaders });
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

    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData.user) {
      return new Response(JSON.stringify({ error: "인증 정보가 없습니다" }), { status: 401, headers: corsHeaders });
    }

    if (userData.user.email !== SUPER_ADMIN_EMAIL) {
      return new Response(JSON.stringify({ error: "플랫폼 관리자만 원장을 초대할 수 있습니다" }), { status: 403, headers: corsHeaders });
    }

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: center, error: centerErr } = await adminClient
      .from("centers")
      .select("id")
      .eq("id", center_id)
      .maybeSingle();

    if (centerErr) {
      return new Response(JSON.stringify({ error: centerErr.message }), { status: 500, headers: corsHeaders });
    }
    if (!center) {
      return new Response(JSON.stringify({ error: "존재하지 않는 원입니다" }), { status: 404, headers: corsHeaders });
    }

    const { data: existing } = await adminClient
      .from("center_owner_invites")
      .select("*")
      .eq("center_id", center_id)
      .eq("email", email)
      .eq("status", "pending")
      .maybeSingle();

    if (existing) {
      return new Response(JSON.stringify({ error: "이미 이 이메일로 대기 중인 초대가 있습니다", invite: existing }), { status: 409, headers: corsHeaders });
    }

    const { error: inviteErr } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { invited_center_id: center_id },
      redirectTo: `${Deno.env.get("SITE_URL")}/center-owner-onboarding.html`,
    });

    if (inviteErr) {
      return new Response(JSON.stringify({ error: inviteErr.message }), { status: 400, headers: corsHeaders });
    }

    const { data: created, error: insertErr } = await adminClient
      .from("center_owner_invites")
      .insert({ center_id, email, status: "pending" })
      .select()
      .single();

    if (insertErr) {
      return new Response(JSON.stringify({ error: insertErr.message }), { status: 500, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ success: true, invite: created }), { status: 200, headers: corsHeaders });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
});
