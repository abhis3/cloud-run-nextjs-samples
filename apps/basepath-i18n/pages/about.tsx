import React from 'react';
import type { GetStaticProps } from 'next';

export const getStaticProps: GetStaticProps = async ({ locale }) => {
  return {
    props: {
      locale: locale || 'en',
    },
  };
};

export default function AboutPage({ locale }: { locale: string }) {
  return (
    <main>
      <h1>{`About Page (${locale})`}</h1>
    </main>
  );
}
