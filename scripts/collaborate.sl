#
# Armitage Collaboration Feature... make no mistake, I'm extremely excited about this.
#

import msf.*;
import armitage.*;
import console.*;

sub createEventLogTab {
	this('$console $client');

	if ($client is $null && $console is $null) {
		$client = [new ConsoleClient: $null, $mclient, "armitage.poll", "armitage.push", $null, "", $null];
        	$console = [new Console: $preferences];
	        [$client setWindow: $console];
		[$client setEcho: $null];
		[$console updatePrompt: "> "];
	}

        [$frame addTab: "Event Log", $console, $null];
}

sub c_client {
	# run this thing in its own thread to avoid really stupid deadlock situations
	return wait(fork({
		local('$handle $client');
		$handle = connect($host, $port);
		$client = newInstance(^RpcConnection, lambda({
			writeObject($handle, @_);
			return readObject($handle);
		}, \$handle));
		return $client;
	}, $host => $1, $port => $2));
}

sub userFingerprint {
	return unpack("H*", digest(values(systemProperties(), @("os.name", "user.home", "os.version")), "MD5"))[0];
}

sub checkForUserConflict {
	cmd($client, $console, "set ARMITAGE_USER", {
		if ($3 ismatch "ARMITAGE_USER => (.*?)\n") {
			local('$user');
			$user = matched();
			if ($user ne userFingerprint()) {
				showError("Congratulations! You're eligible for a free ringtone.

Just kidding. *This is serious*

You're trying to connect to Metasploit when someone else is already 
using it. This won't work. Trust me. 

It is possible to connect a team to Metasploit but you have to 
start Armitage's collaboration server on the Metasploit host. 

To do this:

1. Disconnect all clients from Metasploit

2. Type:

   cd /path/to/metasploit/
   ./armitage --server [host] [port] [user] [pass] [1=SSL, 0=No SSL]

   The [values] must be what you would use to connect Armitage to 
   Metasploit's RPC daemon. Do not use 127.0.0.1 for [host].

3. Reconnect and enjoy the collaboration features.");
			}
		}
		else {
			cmd($client, $console, "setg ARMITAGE_USER " . userFingerprint(), {});
		}
	});
}

sub checkForCollaborationServer {
	cmd($client, $console, "set ARMITAGE_SERVER", {
		if ($3 ismatch "ARMITAGE_SERVER => (.*?):(.*?)/(.*?)\n") {
			local('$host $port $token');
			($host, $port, $token) = matched();
			dispatchEvent(lambda({
				setField(^msf.MeterpreterSession, DEFAULT_WAIT => 20000L);
				setup_collaboration($host, $port, $token);
				postSetup();
			}, \$host, \$port, \$token));
		}
		else {
			warn("No collaboration server is present!");
			$mclient = $client;
			checkForUserConflict();
			dispatchEvent(&postSetup);
		}
	});
}


sub setup_collaboration {
	local('$host $port $ex $nick %r');
	
	$nick = ask("What is your nickname?");

	try {
		$mclient = c_client($1, $2);	
		%r = call($mclient, "armitage.validate", $3, $nick);
		if (%r["success"] eq '1') {
			showError("Collaboration Setup!");
		}
		else {
			showError("Collaboration Connection Failed");
			$mclient = $client;
		}
	}
	catch $ex {
		showError("Collaboration Connection Failed. :(\n" . [$ex getMessage]);
		$mclient = $client;
	}
}

sub uploadFile {
	local('$handle %r $data');

	$handle = openf($1);
	$data = readb($handle, -1);
	closef($handle);

	%r = call($mclient, "armitage.upload", getFileName($1), $data);
	return %r['file'];
}

sub downloadFile {
	local('$file $handle %r');
	%r = call($mclient, "armitage.download", $1);
	$file = getFileName($1);	
	$handle = openf("> $+ $file");
	writeb($handle, %r['data']);
	closef($handle);
	return $file;
}

sub getFileContent {
	local('$file $handle %r');
	if ($mclient !is $client) {
		%r = call($mclient, "armitage.download_nodelete", $1);
		return %r['data'];
	}
	else {
		$handle = openf($1);
		$file = readb($handle, -1);
		closef($handle);
		return $file;
	}
}
