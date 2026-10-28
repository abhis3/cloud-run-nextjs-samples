/** @type {import('next').NextConfig} */
const nextConfig = {
  async headers() {
    return [
      {
        source: '/about',
        headers: [{ key: 'x-about-header', value: '1' }],
      },
    ];
  },
  async redirects() {
    return [
      {
        source: '/old-about',
        destination: '/about',
        permanent: false,
      },
    ];
  },
  async rewrites() {
    return {
      beforeFiles: [
        { source: '/rewrite-before', destination: '/about' },
      ],
      afterFiles: [
        { source: '/rewrite-after', destination: '/about' },
      ],
      fallback: [
        { source: '/rewrite-fallback/:path*', destination: '/api/hello' },
      ],
    };
  },
};
export default nextConfig;
