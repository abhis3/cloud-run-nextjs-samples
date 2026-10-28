import type { NextApiRequest, NextApiResponse } from 'next';

export default function handler(req: NextApiRequest, res: NextApiResponse) {
  res.setHeader('Cache-Control', 'public, s-maxage=300');
  res.setHeader('CDN-Cache-Control', 'public, max-age=600');
  res.status(200).json({ ok: true, route: 'guarded-api' });
}
