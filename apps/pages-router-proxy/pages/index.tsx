import React from 'react';
import type { GetStaticProps } from 'next';

export const getStaticProps: GetStaticProps = async () => {
  return {
    props: {
      page: 'public-home-ssg',
    },
  };
};

export default function PublicHomePage({ page }: { page: string }) {
  return (
    <main>
      <h1>{`Pages Router Public Home (${page})`}</h1>
    </main>
  );
}
