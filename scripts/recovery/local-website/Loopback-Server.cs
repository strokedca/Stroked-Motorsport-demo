using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Collections.Generic;
public sealed class StrokedLocalRequest : IDisposable {
 public TcpClient Client; public NetworkStream Stream; public string Method; public string Target;
 public Dictionary<string,string> Headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
 public byte[] Body;
 public void Reply(int code,string type,byte[] body,string policy,string disposition){
  string reason=code==200?"OK":code==400?"Bad Request":code==403?"Forbidden":code==404?"Not Found":"Error";
  StringBuilder h=new StringBuilder("HTTP/1.1 "+code+" "+reason+"\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nCross-Origin-Resource-Policy: same-origin\r\nCross-Origin-Opener-Policy: same-origin\r\nReferrer-Policy: no-referrer\r\n");
  h.Append("Content-Type: "+type+"\r\nContent-Length: "+body.Length+"\r\n");
  if(!String.IsNullOrEmpty(policy))h.Append("Content-Security-Policy: "+policy+"\r\n");
  if(!String.IsNullOrEmpty(disposition))h.Append("Content-Disposition: "+disposition+"\r\n");
  h.Append("\r\n");byte[] header=Encoding.ASCII.GetBytes(h.ToString());Stream.Write(header,0,header.Length);Stream.Write(body,0,body.Length);Stream.Flush();
 }
 public void Dispose(){if(Stream!=null)Stream.Dispose();if(Client!=null)Client.Close();}
}
public sealed class StrokedLoopbackServer : IDisposable {
 private TcpListener Listener;
 public StrokedLoopbackServer(){Listener=new TcpListener(IPAddress.Loopback,3000);Listener.Start(16);}
 public StrokedLocalRequest Accept(){
  TcpClient client=Listener.AcceptTcpClient();StrokedLocalRequest r=new StrokedLocalRequest();r.Client=client;r.Stream=client.GetStream();r.Stream.ReadTimeout=10000;r.Stream.WriteTimeout=10000;
  try{
   MemoryStream buffer=new MemoryStream();int state=0;
   while(buffer.Length<16384){int c=r.Stream.ReadByte();if(c<0)throw new IOException("Incomplete HTTP header");buffer.WriteByte((byte)c);if((state==0||state==2)&&c==13)state++;else if((state==1||state==3)&&c==10)state++;else state=0;if(state==4)break;}
   if(state!=4)throw new IOException("HTTP header too long");string header=Encoding.ASCII.GetString(buffer.ToArray());buffer.Dispose();string[] lines=header.Split(new string[]{"\r\n"},StringSplitOptions.None);string[] first=lines[0].Split(' ');
   if(first.Length!=3||!first[2].StartsWith("HTTP/1."))throw new IOException("Bad request line");r.Method=first[0];r.Target=first[1];
   for(int i=1;i<lines.Length;i++){int colon=lines[i].IndexOf(':');if(colon<=0)continue;string key=lines[i].Substring(0,colon);if(r.Headers.ContainsKey(key))throw new IOException("Duplicate header");r.Headers.Add(key,lines[i].Substring(colon+1).Trim());}
   if(!r.Headers.ContainsKey("Host")||r.Headers["Host"]!="127.0.0.1:3000"||r.Headers.ContainsKey("Transfer-Encoding"))throw new IOException("Unsupported request scope");
   int length=0;if(r.Headers.ContainsKey("Content-Length")&&(!Int32.TryParse(r.Headers["Content-Length"],out length)||length<0||length>8192))throw new IOException("Body too large");
   r.Body=new byte[length];int offset=0;while(offset<length){int read=r.Stream.Read(r.Body,offset,length-offset);if(read<=0)throw new IOException("Incomplete HTTP body");offset+=read;}
   return r;
  }catch{r.Dispose();throw;}
 }
 public void Dispose(){Listener.Stop();}
}
