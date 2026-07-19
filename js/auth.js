import { getSupabaseClient, isSupabaseConfigured } from "./supabase-client.js";
import { setSharedSession } from "./cnxt-auth.js";

const REDIRECT_PARAM = "redirect";
const DEFAULT_REDIRECT = "https://cnxt.to";

const signInForm = document.querySelector("#sign-in-form");
const signUpForm = document.querySelector("#sign-up-form");
const signInTab = document.querySelector("#show-sign-in");
const signUpTab = document.querySelector("#show-sign-up");
const signInFeedback = document.querySelector("#auth-feedback");
const signUpFeedback = document.querySelector("#auth-feedback-signup");

// --- Tab switching ---

function setActiveTab(mode) {
  const isSignIn = mode === "sign-in";
  signInTab.classList.toggle("auth-tab-active", isSignIn);
  signUpTab.classList.toggle("auth-tab-active", !isSignIn);
  signInForm.classList.toggle("auth-form-hidden", !isSignIn);
  signUpForm.classList.toggle("auth-form-hidden", isSignIn);
  clearFeedback();
}

signInTab.addEventListener("click", () => setActiveTab("sign-in"));
signUpTab.addEventListener("click", () => setActiveTab("sign-up"));

// --- Feedback ---

function setFeedback(el, message = "", mode = "idle") {
  el.textContent = message;
  el.dataset.mode = mode;
  el.classList.toggle("is-visible", Boolean(message));
}

function clearFeedback() {
  setFeedback(signInFeedback);
  setFeedback(signUpFeedback);
}

// --- Redirect ---

function getRedirectUrl() {
  const params = new URLSearchParams(window.location.search);
  const redirect = params.get(REDIRECT_PARAM);
  if (!redirect) return DEFAULT_REDIRECT;

  // Only allow redirects to cnxt.to domains
  try {
    const url = new URL(redirect);
    if (url.hostname.endsWith(".cnxt.to") || url.hostname === "cnxt.to") {
      return redirect;
    }
  } catch {}
  return DEFAULT_REDIRECT;
}

function doRedirect() {
  window.location.href = getRedirectUrl();
}

// --- Supabase client ---

async function getClient() {
  if (!isSupabaseConfigured()) {
    setFeedback(signInFeedback, "Authentication is temporarily unavailable.", "error");
    return null;
  }
  try {
    return await getSupabaseClient();
  } catch {
    setFeedback(signInFeedback, "Unable to connect. Please try again shortly.", "error");
    return null;
  }
}

// --- Check existing session ---
// NOTE: We intentionally do NOT auto-redirect on load. Auto-redirecting
// whenever a session exists (in auth.cnxt.to's own localStorage) bounced
// users straight back to the redirect target, preventing them from ever
// seeing the sign-in form. The submit handlers below already redirect
// after a successful sign-in/sign-up.

async function checkExistingSession() {
  // No-op: do not auto-redirect on page load.
}

// --- Sign In ---

signInForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const client = await getClient();
  if (!client) return;

  const formData = new FormData(signInForm);
  const email = String(formData.get("email") || "").trim();
  const password = String(formData.get("password") || "");

  if (!email || !password) {
    setFeedback(signInFeedback, "Please enter your email and password.", "error");
    return;
  }

  setFeedback(signInFeedback, "Signing in…", "idle");
  const { error } = await client.auth.signInWithPassword({ email, password });

  if (error) {
    setFeedback(signInFeedback, error.message, "error");
    return;
  }

  // Persist session to .cnxt.to cookie for cross-domain auth
  await setSharedSession();

  signInForm.reset();
  setFeedback(signInFeedback, "Signed in! Redirecting…", "success");
  doRedirect();
});

// --- Sign Up ---

signUpForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const client = await getClient();
  if (!client) return;

  const formData = new FormData(signUpForm);
  const email = String(formData.get("email") || "").trim();
  const password = String(formData.get("password") || "");
  const confirm = String(formData.get("confirm") || "");
  const termsAccepted = formData.get("terms") === "on";
  const newsletter = formData.get("newsletter") === "on";

  if (!email || !password) {
    setFeedback(signUpFeedback, "Please fill in all fields.", "error");
    return;
  }

  if (password !== confirm) {
    setFeedback(signUpFeedback, "Passwords do not match.", "error");
    return;
  }

  if (password.length < 6) {
    setFeedback(signUpFeedback, "Password must be at least 6 characters.", "error");
    return;
  }

  if (!termsAccepted) {
    setFeedback(signUpFeedback, "Please agree to the Terms of Service and Privacy Policy.", "error");
    return;
  }

  setFeedback(signUpFeedback, "Creating your account…", "idle");
  const { data, error } = await client.auth.signUp({ email, password });

  if (error) {
    setFeedback(signUpFeedback, error.message, "error");
    return;
  }

  // Record terms acceptance and newsletter preference
  if (data?.user?.id) {
    try {
      // Insert terms agreement
      await client
        .from("terms_agreements")
        .insert({ user_id: data.user.id, terms_version: "1.0", privacy_version: "1.0" });

      // Insert newsletter subscription if opted in
      if (newsletter) {
        await client
          .from("newsletter_subscriptions")
          .insert({ user_id: data.user.id, email, subscribed: true });
      }
    } catch { /* non-critical */ }
  }

  signUpForm.reset();

  // If Supabase auto-signed-in (email confirmation disabled), persist the cookie
  if (data?.session?.user) {
    await setSharedSession();
    setFeedback(signUpFeedback, "Account created! Redirecting…", "success");
    doRedirect();
    return;
  }

  setFeedback(signUpFeedback, "Account created! Check your email to confirm, then sign in.", "success");
});

// --- Init ---

checkExistingSession();
