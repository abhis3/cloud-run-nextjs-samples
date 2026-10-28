import React from 'react';
import type { GetStaticProps } from 'next';

export const getStaticProps: GetStaticProps = async () => {
  return {
    props: {
      page: 'public-isr',
    },
    revalidate: 60,
  };
};

export default function PublicIsrPage({ page }: { page: string }) {
  return (
    <main>
      <h1>{`Pages Router Public ISR (${page})`}</h1>
    </main>
  );
}
