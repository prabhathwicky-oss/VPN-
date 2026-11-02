// Verifies a Google Play subscription purchase (new purchase or restore)
// on the server and upgrades the caller's plan.
import { getProfile, effectivePlan, handler, HttpError, json, readJson, requireUser } from "../_shared/common.ts";
import { syncPurchase } from "../_shared/google.ts";

Deno.serve(handler(async (req) => {
  const user = await requireUser(req);
  const { purchase_token } = await readJson<{ purchase_token?: string; product_id?: string }>(req);
  if (!purchase_token) throw new HttpError(400, "bad_request", "purchase_token required");

  let row;
  try {
    row = await syncPurchase(purchase_token, user.id);
  } catch (e) {
    console.error(e);
    throw new HttpError(502, "verify_failed", "Could not verify the purchase with Google Play. Please try again.");
  }
  const profile = await getProfile(user.id);
  return json({
    ok: true,
    state: row?.state,
    plan: effectivePlan(profile),
    expires_at: profile.plan_expires_at,
  });
}));
