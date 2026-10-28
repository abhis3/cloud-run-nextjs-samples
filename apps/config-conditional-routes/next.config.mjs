/** @type {import('next').NextConfig} */
const nextConfig = {
  async headers() {
    return [
      {
        source: '/pricing',
        has: [{ type: 'header', key: 'x-tier', value: 'enterprise' }],
        headers: [{ key: 'x-pricing-variant', value: 'enterprise' }],
      },
      {
        source: '/offer',
        has: [{ type: 'cookie', key: 'tier', value: 'vip' }],
        headers: [{ key: 'x-offer-variant', value: 'vip' }],
      },
    ];
  },
  async rewrites() {
    return {
      beforeFiles: [
        {
          source: '/pricing',
          has: [{ type: 'header', key: 'x-tier', value: 'enterprise' }],
          destination: '/pricing-enterprise',
        },
        {
          source: '/offer',
          has: [{ type: 'cookie', key: 'tier', value: 'vip' }],
          destination: '/banner-vip',
        },
        {
          source: '/offer',
          missing: [{ type: 'cookie', key: 'tier', value: 'vip' }],
          destination: '/banner-default',
        },
      ],
    };
  },
};

export default nextConfig;
