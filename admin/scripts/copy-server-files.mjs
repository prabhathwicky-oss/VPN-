// Publishes the node installer + agent from /server so new VPN servers can
// fetch them from https://<admin-site>/install.sh and /agent.py
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, "..", "..", "server");
const dst = join(here, "..", "public");
mkdirSync(dst, { recursive: true });
for (const f of ["install.sh", "agent.py"]) {
  const from = join(src, f);
  if (existsSync(from)) copyFileSync(from, join(dst, f));
  else if (!existsSync(join(dst, f))) console.warn(`warning: ${from} not found`);
}
console.log("server files copied to public/");
