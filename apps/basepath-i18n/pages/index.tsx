import React from 'react';
import type { GetStaticProps } from 'next';

export const getStaticProps: GetStaticProps = async ({ locale }) => {
  return {
    props: {
      locale: locale || 'en',
    },
  };
};

export default function HomePage({ locale }: { locale: string }) {
  return (
    <main>
      <h1>{`Home Page (${locale})`}</h1>
    </main>
  );
}
