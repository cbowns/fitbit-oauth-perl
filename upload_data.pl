#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/.";

use Data::Dumper;

use OAuthSimple;
use WWW::Curl::Easy;
use WWW::Curl::Form;
use CGI::Simple;

use Text::CSV;

# Set debug to 1 for great log messages:
my $DEBUG = 0;

my $accept_language_key = "Accept-Language";
# If your weights are in kilograms, try en_UK.
my $accept_language_value = "en_US";

$oauth = new OAuthSimple();
# Set the action type to POST, otherwise the base string is wrong.
$oauth->setAction(POST);

# Read API keys from ~/.api_keys
# or just fill these in with your
# app's values from https://dev.fitbit.com/apps

# Put your home directory path here:
my $home = $ENV{HOME};

# Where's your CSV? Mine is next to this script:
my $file = "weightbot_data.csv";

my %keys;
$keys{oauth_consumer_key} = "oauth_consumer_key";
$keys{oauth_shared_secret} = "oauth_shared_secret";

$keys{oauth_token} = "oauth_token";
$keys{oauth_token_secret} = "oauth_token_secret";

# .api_keys prefix:
$keys{api_keys_prefix} = "fitbit_uploader";

sub fetchkey {
	my @keysToRead = ( keys(%keys) );
	my $file = "$home/.api_keys";
	
	open(MYINPUTFILE, "<$file") or die "Couldn't open '$file': $!";
	print "Reading API keys from $file:\n" if $DEBUG;
	my (@lines) = <MYINPUTFILE>; # read file into list

	for my $line (@lines) {
		my @linekeys = split('=', $line);
		
		foreach $key (@keysToRead) {
			my $searchVar = $keys{api_keys_prefix} . "_" . $key;
			
			if ($linekeys[0] eq $searchVar) {
				my $value = $linekeys[1];
				chomp($value);
				
				print "Setting $key to $value\n" if $DEBUG;

				$keys{$key} = $value;
			}
		}
	}
	close(MYINPUTFILE);
}

fetchkey();

my $weight_key = "weight";
my $date_key = "date";

my $api_version = "1";
my $response_format = "json";
my $api_base_url = "http://api.fitbit.com";
my $info_get_url = "/$api_version/user/-/profile.$response_format";
my $weight_post_url = "/$api_version/user/-/body/log/weight.$response_format";
my $full_post_url = $api_base_url . $weight_post_url;

print "Uploading to $full_post_url\n" if $DEBUG;

my $csv = Text::CSV->new({ sep_char => ',' });
  
open(my $data, '<', $file) or die "Couldn't open '$file' $!\n";

my $count = 0;
my @previous_field;
my @field;

while (my $line = <$data>) {
    # skip first line (headers)
    next if 1..1;
    
	$count++;
	chomp $line;
	
	print "---\nRecord #$count:\n" if $DEBUG;
	print "Line: $line\n" if $DEBUG;

	# Parse the line:
	if ($csv->parse($line)) {
		@previous_field = @field;
		@field = $csv->fields();

		my $weight = $field[2];
		my $date = $field[0];
		chomp($weight);
		chomp($date);

		print "Posting weight $weight on date $date\n";

		# Upload:
		$oauth->reset();
		$signedpost = $oauth->sign(
			{
				path => $full_post_url,
				signatures => {
						oauth_consumer_key => $keys{oauth_consumer_key},
						shared_secret => $keys{oauth_shared_secret},
						oauth_token => $keys{oauth_token},
						oauth_secret => $keys{oauth_token_secret},
				},
				parameters => {
					weight => $weight,
					date => $date,
				}
			}
		);

		# Debug logging of the signing object and request URLs:
		# print "———————————————————————————————————————\n" if $DEBUG;
		# print Dumper($signedpost) if $DEBUG;
		# print "———————————————————————————————————————\n" if $DEBUG;

		# print "Post URL: $full_post_url\n" if $DEBUG;
		# print "———————————————————————————————————————\n" if $DEBUG;

		# Post a record:

		# Make form data:
		my $curlf = new WWW::Curl::Form;
		$curlf->formadd($weight_key, $weight);
		$curlf->formadd($date_key, $date);

		# Make a post request:
		my $postcurl = WWW::Curl::Easy->new();
		$postcurl->setopt( CURLOPT_URL, $full_post_url );

		# set the auth and language headers:
		my @httpheaders = ["Authorization: $signedpost->{header}", "$accept_language_key: $accept_language_value" ];
		$postcurl->pushopt( CURLOPT_HTTPHEADER, @httpheaders );

		# debugging proxy:
		# $postcurl->setopt( CURLOPT_PROXY, "127.0.0.1");
		# $postcurl->setopt( CURLOPT_PROXYPORT, "8888");

		# Set the form data:
		$postcurl->setopt(CURLOPT_HTTPPOST, $curlf);

		# Set up the response body:
		my $postcurl_responsebody;
		$postcurl->setopt(CURLOPT_WRITEDATA,\$postcurl_responsebody);

		# Post the data:
		my $request_retcode = $postcurl->perform;
		my ($request_success, $response_code) = checkreturncode($postcurl, $request_retcode);

		# Parse the response:
		my $q = new CGI::Simple($postcurl_responsebody);

		if ($request_success && ( $response_code == 200 || $response_code == 201) ) {
			print "Success!";
			print " Response:\n" if $DEBUG;
			print "$postcurl_responsebody\n" if $DEBUG;
		} else {
			print("Failed to post data.\n");
			print "Response was:\n" if $DEBUG;
			print Dumper($postcurl_responsebody) if $DEBUG;
			exit 1;
		}

	} else {
		warn "Line could not be parsed: $line\n";
	}
}

sub checkreturncode
{
	# Starts the actual request
	my $curl = $_[0];
	my $retcode = $_[1];
	# Looking at the results...
	if ($retcode == 0) {
		my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
		# print("Received response: $response_body\n");
		if ($response_code != 200 && $response_code != 201) {
			print "Got a non-200 reply: $response_code\n";
		}
		return (1, $response_code);
		# judge result and next action based on $response_code
	} else {
		# Error code, type of error, error message
		print("An error happened: $retcode:\n".$curl->strerror($retcode)."\n".$curl->errbuf."\n");
		return 0;
	}
}
