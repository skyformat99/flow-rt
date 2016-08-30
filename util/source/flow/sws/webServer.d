/**
This file is part of DSWS.

DSWS is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or 
any later version.

DSWS is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with DSWS.  If not, see <http://www.gnu.org/licenses/>.
*/

module flow.sws.webServer; 

import std.socket, core.thread;

import flow.dev;
import flow.base.type;

import core.time;
import std.stdio, std.file, std.string, std.array, std.conv, std.datetime, std.uuid, std.json, std.algorithm;

import flow.sws.webClient, flow.sws.webRequest; 

class WebListener : Thread
{
	private Socket _listener;
	private WebServer _server;

	bool stopping;

	this(Socket listener, WebServer server)
	{
		this._listener = listener;
		this._server = server;

		super(&this.run);
	}

	private void run()
	{
		try
		{
			Socket sock = this._listener.accept();

			if(!this.stopping)
			{
				WebClient webClient = new WebClient(sock, this._server);
				webClient.start();
			}
		}
		finally
		{
			this._server._listeners.remove(this);
		}
	}
}

/**
 * The HTTP server class
 */
class WebServer : Thread {
	
	Socket listener;
	ushort listenerAmount = 10;
	
	private bool _stopping;

	ulong requestNumber = 0;
	int uploadingClients = 0;
	
	protected string[string] settings;
	
	protected ushort port;
	public bool listening;
	
	protected bool delegate(WebRequest request) httpDg = null;
	protected bool delegate(WebRequest request, string message) wsDg = null;
	
	this() { 
		setPort(80);
		listener = new TcpSocket;
		super(&run);
	}
	
	this(bool delegate(WebRequest request) httpDg, bool delegate(WebRequest request, string message) wsDg = null) {
		this();
		this.httpDg = httpDg;
		this.wsDg = wsDg;
	} 
	
	/**
	 * Proces a request. This metod must be called after the request set all the POST, GET, FILES, COOKIES
	 * 
	 * @return bool return true if the process is a success 
	 */
	public bool processRequest(WebRequest request) {
		
		if(httpDg !is null) {
			return httpDg(request);
		} 
		
		return false;
	}
	
	/**
	 * Proces a message via websockets
	 * 
	 * @return bool return true if the process is a success 
	 */
	public bool processMessage(WebRequest request, string message) {
		
		if(wsDg !is null) {
			return wsDg(request, message); 
		} 
		
		return false;
	}
	
	/**
	 * Set the listening port
	 * @param ushort port 
	 */
	void setPort(ushort port) {
		this.port = port;
	}
	
	/**
	 * Start the server
	 */
	private void run() {
		writeln("starting  webserver on port " ~ to!string(port) ~ "...");
		stdout.flush;
		
		listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		bool binded = false;
		
		while(!binded) {
			try {
				listener.bind(new InternetAddress(port));
				binded = true;
			} catch(Exception e) {
				writeln(e.msg);
				stdout.flush;
				
				this.sleep( dur!("seconds")( 2 ) ); // sleep for 2 seconds
			}
		}
		
		listener.listen(1);
		
		writeln("waiting for clients...");
		stdout.flush;
		
		listening = true;
		
		listener.blocking(true);

		this._listeners = new List!WebListener;

		while(!this._stopping) {
			if(this._listeners.length < this.listenerAmount)
			{
				auto l = new WebListener(listener, this);
				l.start();
				this._listeners.put(l);
			}
			else Thread.sleep(WAITINGTIME);
	    }

		foreach(l; this._listeners)
			l.stopping = true;
	}

	private List!WebListener _listeners;
	
	/**
	 * Get the path where the temporarry files will be uploaded
	 * 
	 * @return string
	 */
	public string getTempFilePath() {
		return "";
	}
	
	/**
	 * Stop the server
	 */
	void stop() {
		writeln("close the listener");
		
		this._stopping = true;

		try {
			if(listener.isAlive) {
				listener.close;
			}
		} catch(Exception e) {
			writeln(e);
		}
		
		listening = false;
	}
}