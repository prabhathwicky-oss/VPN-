// Google Play Real-time Developer Notifications (Pub/Sub push endpoint).
// Configure the push subscription URL as:
//   https://<project>.supabase.co/functions/v1/play-rtdn?token=<RTDN_TOKEN>
import { handler, HttpError, json, readJson } from "../_shared/common.ts";
import { syncPurchase } from "../_shared/google.ts";

Deno.serve(handler(async (req) => {
  const token = new URL(req.url).searchParams.get("token");
  const expected = Deno.env.get("RTDN_TOKEN");
  if (!expected || token !== expected) throw new HttpError(401, "unauthorized", "bad token");

  const body = await readJson<{ message?: { data?: string } }>(req);
  const data = body.message?.data;
  if (!data) return json({ ok: true, skipped: "no data" });

  const decoded = JSON.parse(atob(data));
  const purchaseToken: string | undefined = decoded.subscriptionNotification?.purchaseToken;
  if (decoded.testNotification) return json({ ok: true, test: true });
  if (!purchaseToken) return json({ ok: true, skipped: "not a subscription notification" });

  try {
    await syncPurchase(purchaseToken); // owner resolved from stored row
  } catch (e) {
    console.error("rtdn sync failed", e);
    // Non-2xx makes Pub/Sub retry later.
    return json({ ok: false }, 500);
  }
  return json({ ok: true });
}));
