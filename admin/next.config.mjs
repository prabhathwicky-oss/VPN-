/** @type {import('next').NextConfig} */
const nextConfig = {
  poweredByHeader: false,
  async headers() {
    return [
      // install.sh / agent.py are fetched by servers with curl
      { source: "/install.sh", headers: [{ key: "Content-Type", value: "text/x-shellscript; charset=utf-8" }] },
      { source: "/agent.py", headers: [{ key: "Content-Type", value: "text/x-python; charset=utf-8" }] },
    ];
  },
};
export default nextConfig;
