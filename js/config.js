// ============================================================
// SUPABASE CONFIG
// Ganti SUPABASE_URL dan SUPABASE_ANON_KEY dengan milik Anda
// Dapatkan dari: Supabase Dashboard > Settings > API
// ============================================================

const SUPABASE_URL = 'https://fxdvnnxdiufymwqxtgxm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ4ZHZubnhkaXVmeW13cXh0Z3htIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0OTYzMzMsImV4cCI6MjA5NDA3MjMzM30.rZo1gGw-3MkCMTbJKwT_ARZqVJw7ZfxWg1q2VAjlXKw';

// CDN sudah membuat global 'supabase' — reassign saja, jangan deklarasi ulang
supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
