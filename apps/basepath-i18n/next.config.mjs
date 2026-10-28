/** @type {import('next').NextConfig} */
const nextConfig = {
  basePath: '/base',
  i18n: {
    locales: ['en', 'fr', 'de'],
    defaultLocale: 'en',
    localeDetection: false,
  },
};

export default nextConfig;
