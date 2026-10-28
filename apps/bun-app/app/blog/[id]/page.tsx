import React from 'react';
export const revalidate = 60;
export async function generateStaticParams() {
  return [{ id: 'a' }, { id: 'b' }];
}
export default async function BlogPostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <div>Blog Post {id}</div>;
}
