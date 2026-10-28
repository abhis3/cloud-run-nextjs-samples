import React from 'react';
import type { GetStaticProps } from 'next';

export const getStaticProps: GetStaticProps = async ({ locale }) => {
  return {
    props: {
      locale: locale || 'en',
    },
  };
};

export default function DashboardPage({ locale }: { locale: string }) {
  return (
    <main>
      <h1>{`Dashboard SSG Page (${locale})`}</h1>
    </main>
  );
}
