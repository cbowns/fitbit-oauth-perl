#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/.";
use Data::Dumper;

use OAuthSimple;
use WWW::Curl::Easy;
use CGI::Simple;

# Set debug to 1 for great log messages:
my $DEBUG = 0;

$oauth = new OAuthSimple();

# Read API keys from ~/.api_keys
# or just fill these in with your
# app's values from https://dev.fitbit.com/apps

# Put your home directory path here:
my $home = ;

my %keys;
$keys{oauth_consumer_key} = "oauth_consumer_key";
$keys{oauth_shared_secret} = "oauth_shared_secret";
$keys{api_keys_prefix} = "fitbit_uploader";

sub fetchkey()
{
	my @keysToRead = ( keys(%keys) );
	my $file = "$home/.api_keys";
	open(MYINPUTFILE, "<$file"); # open for input
	print "Reading API keys from $file:\n" if $DEBUG;
	my(@lines) = <MYINPUTFILE>; # read file into list
	my($line);
	foreach $line (@lines) # loop thru list
	{
		my @linekeys = split('=', $line);
		foreach $key (@keysToRead) {
			my $searchVar = $keys{api_keys_prefix} . "_" . $key;
			if (@linekeys[0] eq $searchVar) {
				my $value = @linekeys[1];
				chomp($value);
				print "Setting $key to $value\n" if $DEBUG;
				$keys{$key} = $value;
			}
		}
	}
	close(MYINPUTFILE);
}

fetchkey();

my $oauth_request_url = "http://api.fitbit.com/oauth/request_token";
my $oauth_redeem_token_url = "http://www.fitbit.com/oauth/authorize?oauth_token=";
my $oauth_access_token_url = "http://api.fitbit.com/oauth/access_token";

my $oauth_token;
my $oauth_token_secret;
my $oauth_callback_confirmed;
my $oauth_encoded_user;

$oauthrequest = $oauth->sign(
	{
		path => $oauth_request_url,
		signatures=>{
				oauth_consumer_key => $keys{oauth_consumer_key},
				shared_secret => $keys{oauth_shared_secret},
		},
		parameters=>{}
	}
);

print "Request URL: $oauthrequest->{signed_url}\n" if $DEBUG;

# Request the token:
my $requestcurl = WWW::Curl::Easy->new();
$requestcurl->setopt( CURLOPT_URL, $oauthrequest->{signed_url} );

my $requestcurl_responsebody;
$requestcurl->setopt(CURLOPT_WRITEDATA,\$requestcurl_responsebody);

# Request the token:
my $request_retcode = $requestcurl->perform;
my $request_success = checkreturncode($requestcurl, $request_retcode);

# Parse the response:
my $q = new CGI::Simple($requestcurl_responsebody);

if ($request_success) {
	$oauth_token = $q->{oauth_token}->[0];
	$oauth_token_secret = $q->{oauth_token_secret}->[0];
	$oauth_callback_confirmed = $q->{oauth_callback_confirmed}->[0];
	print("Successfully got a token:\n") if $DEBUG;
	print "$oauth_token\n" if $DEBUG;
	print "Temporary secret:\n" if $DEBUG;
	print $oauth_token_secret . "\n" if $DEBUG;
} else {
	print("Failed to get a token.\n");
	print "Response was:\n" if $DEBUG;
	print Dumper($q) if $DEBUG;
	exit 1;
}

# Use the token to request access:

my $authorizecurl = WWW::Curl::Easy->new();
my $tokenauthurl = $oauth_redeem_token_url . $oauth_token;
print "Opening auth request URL in a browser: $tokenauthurl\n" if $DEBUG;
`open $tokenauthurl`;

# Wait for the user to enter their PIN:

print "Enter your PIN from fitbit.com:\n";
$oauth_verifier = <>;
chomp($oauth_verifier);

print "Verifier code: $oauth_verifier\n" if $DEBUG;

# Request a permanent token with the pin:

$oauthaccess = $oauth->sign(
	{
		path => $oauth_access_token_url,
		signatures => {
			oauth_consumer_key => $keys{oauth_consumer_key},
			shared_secret => $keys{oauth_shared_secret},
# populated from previous request:
			oauth_token => $oauth_token,
			oauth_secret => $oauth_token_secret,
		},
		parameters => {
			oauth_verifier => $oauth_verifier,
		}
	}
);

print "Token access URL: $oauthaccess->{signed_url}\n" if $DEBUG;

# Request the token:
my $accesscurl = WWW::Curl::Easy->new();
$accesscurl->setopt( CURLOPT_URL, $oauthaccess->{signed_url} );
# A filehandle, reference to a scalar or reference to a typeglob can be used here.
my $accesscurl_responsebody;
$accesscurl->setopt(CURLOPT_WRITEDATA,\$accesscurl_responsebody);

# access a token:
my $access_retcode = $accesscurl->perform;
my ($access_success, $access_responsecode) = checkreturncode($accesscurl, $access_retcode);

# Parse the response:
my $q = new CGI::Simple($accesscurl_responsebody);
my $oauth_token;
my $oauth_token_secret;
my $encoded_user_id;

if ($access_success) {
	if ($access_responsecode != 200) {
		print "Something went wrong, got code $access_responsecode when redeeming the OAuth access code for a token.\n";
		print Dumper($accesscurl_responsebody) if $DEBUG;
		exit 1;
	}
	$oauth_token = $q->{oauth_token}->[0];
	$oauth_token_secret = $q->{oauth_token_secret}->[0];
	$oauth_encoded_user = $q->{encoded_user_id}->[0];
	print "OAuth Token:\n";
	print "$oauth_token\n";
	print "OAuth Token Secret:\n";
	print "$oauth_token_secret\n";
} else {
	print("Failed to get a token.\n");
	print "Response was:\n" if $DEBUG;
	print Dumper($q) if $DEBUG;
	exit 1;
}



sub checkreturncode
{
	# Starts the actual request
	my $requestcurl = $_[0];
	my $retcode = $_[1];
	# Looking at the results...
	if ($retcode == 0) {
		my $response_code = $requestcurl->getinfo(CURLINFO_HTTP_CODE);
		# print("Received response: $response_body\n");
		if ($response_code != 200) {
			print "Got response code $response_code\n";
		}
		return (1, $response_code);
		# judge result and next action based on $response_code
	} else {
		# Error code, type of error, error message
		print("An error happened: $retcode:\n".$requestcurl->strerror($retcode)."\n".$requestcurl->errbuf."\n");
		return 0;
	}
}
