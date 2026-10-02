import {NextResponse} from 'next/server';
export async function GET(){return NextResponse.json({status:'ok',service:'savixprime-web',environment:process.env.NODE_ENV,liveLedger:false});}
