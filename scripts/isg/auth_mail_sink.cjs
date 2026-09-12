// Disposable network-none test client. Memory only: never logs or writes mail/OTP contents.
// This program is passed to the owned client container; it is not an application SMTP server.
const net = require('node:net');
const http = require('node:http');
const messages = [];
net.createServer(socket => {
  socket.setTimeout(10000, () => socket.destroy());
  socket.write('220 localhost test SMTP\r\n');
  let buffer = '', data = false, body = '', recipient = '';
  socket.on('error', () => {});
  socket.on('data', bytes => {
    buffer += bytes.toString('utf8');
    if (buffer.length + body.length > 128 * 1024) return socket.destroy();
    while (buffer.includes('\r\n')) {
      const end = buffer.indexOf('\r\n'), line = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      if (data) {
        if (line === '.') {
          messages.push({recipient, body}); if (messages.length > 32) messages.shift();
          data = false; body = ''; socket.write('250 accepted\r\n');
        } else body += line.replace(/^\.\./, '.') + '\r\n';
      } else if (/^(EHLO|HELO) /i.test(line)) socket.write('250 localhost\r\n');
      else if (/^RCPT TO:/i.test(line)) { recipient = line.slice(8).trim(); socket.write('250 ok\r\n'); }
      else if (/^DATA$/i.test(line)) { data = true; socket.write('354 send data\r\n'); }
      else if (/^QUIT$/i.test(line)) socket.end('221 goodbye\r\n');
      else socket.write('250 ok\r\n');
    }
  });
}).listen(2525, '127.0.0.1');
http.createServer((req,res) => {
  if (req.method !== 'GET') { res.writeHead(405); return res.end(); }
  if (req.url === '/template') { res.setHeader('Content-Type','text/html'); return res.end('<html><body>TEST-CODE: {{ .Token }}</body></html>'); }
  if (req.url !== '/messages') { res.writeHead(404); return res.end(); }
  res.setHeader('Content-Type','application/json'); res.end(JSON.stringify(messages));
}).listen(10000, '127.0.0.1');
