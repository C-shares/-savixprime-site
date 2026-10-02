'use client';
import { FormEvent, useState } from 'react';
import Link from 'next/link';
import { ArrowRight, ShieldCheck } from 'lucide-react';
import { supabaseBrowser } from '../../lib/supabase';

export default function Login() {
  const [email,setEmail]=useState(''); const [password,setPassword]=useState('');
  const [msg,setMsg]=useState(''); const [busy,setBusy]=useState(false);
  async function submit(e:FormEvent){e.preventDefault();setBusy(true);setMsg('');try{const sb=supabaseBrowser();const {error}=await sb.auth.signInWithPassword({email,password});if(error)throw error;window.location.href='/dashboard';}catch(err){setMsg(err instanceof Error?err.message:'Unable to sign in. Check your details and Supabase settings.');}finally{setBusy(false);}}
  return <main className="authPage"><div className="authCard glass"><div className="brand"><div className="logo">SP</div><div><div className="brandName">Savix<span>Prime</span></div><div className="eyebrow">SECURE ACCESS</div></div></div><h1>Sign in</h1><p className="muted">Sign in using your SavixPrime account.</p><form onSubmit={submit}><label>Email<input type="email" required autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="you@example.com"/></label><label>Password<input type="password" required autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="Your password"/></label><button className="btn btn-primary full" disabled={busy} type="submit">{busy?'Signing in…':'Continue'} <ArrowRight size={16}/></button></form>{msg&&<div className="notice" role="alert">{msg}</div>}<p className="muted small">New here? <Link href="/register">Create an account</Link></p><div className="secure"><ShieldCheck size={18}/><span>Account access is handled by Supabase Authentication. Financial services are not enabled by this sign-in.</span></div><a className="back" href="/">← Back to SavixPrime</a></div></main>
}
