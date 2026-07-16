// Delete the caller's own Supabase account (Apple Guideline 5.1.1(v)).
//
// Deploy:
//   supabase functions deploy delete-account
//
// Requires project secrets SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (set automatically
// when deploying via Supabase CLI linked to the project).
//
// Flow: verify user JWT → delete user_track_metadata (no FK) → remove playlist-covers
// under {user_id}/ → auth.admin.deleteUser (CASCADE cleans other user-scoped tables).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return jsonResponse({ error: "Server misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonResponse({ error: "Missing authorization" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return jsonResponse({ error: "Invalid session" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const userId = user.id;
  const userIdLower = userId.toLowerCase();

  // user_track_metadata.user_id is TEXT without FK — delete both casings to be safe.
  const { error: metaError } = await admin
    .from("user_track_metadata")
    .delete()
    .or(`user_id.eq.${userId},user_id.eq.${userIdLower}`);

  if (metaError) {
    console.error("user_track_metadata delete failed", metaError);
    return jsonResponse({ error: "Failed to delete metadata" }, 500);
  }

  await removeStoragePrefix(admin, "playlist-covers", `${userId}/`);
  if (userId !== userIdLower) {
    await removeStoragePrefix(admin, "playlist-covers", `${userIdLower}/`);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error("auth.admin.deleteUser failed", deleteError);
    return jsonResponse({ error: "Failed to delete account" }, 500);
  }

  return jsonResponse({ ok: true }, 200);
});

async function removeStoragePrefix(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
) {
  const folder = prefix.replace(/\/$/, "");
  const { data: objects, error } = await admin.storage.from(bucket).list(folder, {
    limit: 1000,
  });
  if (error) {
    // Folder may not exist — ignore.
    console.warn("storage list", folder, error.message);
    return;
  }
  if (!objects?.length) return;

  const paths = objects
    .filter((o) => o.name)
    .map((o) => `${folder}/${o.name}`);

  if (paths.length === 0) return;

  const { error: removeError } = await admin.storage.from(bucket).remove(paths);
  if (removeError) {
    console.warn("storage remove", removeError.message);
  }
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
