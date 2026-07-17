import { supabaseConfig } from "./supabase-config.js";

let supabaseClientPromise = null;

export function isSupabaseConfigured() {
  return Boolean(supabaseConfig.url && supabaseConfig.anonKey);
}

export async function getSupabaseClient() {
  if (!isSupabaseConfigured()) {
    throw new Error("Supabase configuration missing.");
  }

  if (!supabaseClientPromise) {
    supabaseClientPromise = import("https://esm.sh/@supabase/supabase-js@2").then(({ createClient }) =>
      createClient(supabaseConfig.url, supabaseConfig.anonKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
        },
      })
    );
  }

  return supabaseClientPromise;
}
