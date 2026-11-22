function Get-DrillKeys([string]$CLI,[string]$WorkDir) {
    $anon='';$service=''
    $kong=Get-ContainerValues (Get-DrillContainer 'supabase_kong_StrokedRecoverySite' -RequireRunning)
    if($kong['SUPABASE_ANON_KEY']){$anon=[string]$kong['SUPABASE_ANON_KEY']}
    foreach($key in @('SUPABASE_SERVICE_KEY','SUPABASE_SERVICE_ROLE_KEY')){if($kong[$key]){$service=[string]$kong[$key];break}}
    if(-not $anon -or -not $service){
        $help=Invoke-QuietNative $CLI @('status','--help')
        if($help -notmatch '--output' -or $help -notmatch '--workdir'){throw 'Local status output flags require review.'}
        $status=ConvertFrom-Json -InputObject (Invoke-QuietNative $CLI @('status','--workdir',$WorkDir,'--output','json'))
        if($status.values){$status=$status.values}
        $url=[Uri]([string]$status.API_URL)
        if($url.Scheme -cne 'http' -or $url.Host -cne '127.0.0.1' -or $url.Port -ne 54321){throw 'Unexpected local API URL in status.'}
        if(-not $anon){$anon=[string]$status.ANON_KEY};if(-not $service){$service=[string]$status.SERVICE_ROLE_KEY}
    }
    foreach($pair in @(@($anon,'anon'),@($service,'service_role'))){
        $parts=$pair[0].Split('.')
        if($parts.Count -ne 3){throw 'Expected legacy local JWT credentials were not available.'}
        $cell=$parts[1].Replace('-','+').Replace('_','/')
        while($cell.Length%4){$cell+='='}
        $claims=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cell)) | ConvertFrom-Json
        if($claims.role -cne $pair[1]){throw 'Unexpected role in a local API key.'}
    }
    return [pscustomobject]@{Anon=$anon;Service=$service;API='http://127.0.0.1:54321'}
}
function Wait-DrillAPI($Keys) {
    $ready=$false
    for($i=0;$i -lt 40;$i++){
        try{$r=Invoke-DrillHTTP 'http://127.0.0.1:54321/auth/v1/settings' 'GET' @{apikey=$Keys.Anon};if($r.Status -eq 200){$ready=$true;break}}catch{}
        Start-Sleep -Milliseconds 500
    }
    if(-not $ready){throw 'The isolated local Auth API did not become ready.'}
}
function Get-DrillEncodedObjectPath([string]$Bucket,[string]$Key) {
    if($Bucket -cnotmatch '^[a-z0-9][a-z0-9_-]{0,99}$' -or -not $Key -or $Key.Contains('\') -or $Key -match '(^|/)\.{1,2}(/|$)'){throw 'Unexpected storage object path.'}
    return [Uri]::EscapeDataString($Bucket)+'/'+(@($Key.Split('/') | ForEach-Object {[Uri]::EscapeDataString($_)}) -join '/')
}
function Restore-DrillObjects([string]$FilesZip,$Manifest,$Keys) {
    $zip=[IO.Compression.ZipFile]::OpenRead($FilesZip)
    $checked=0
    try {
        $entries=Get-StrokedZipFileEntries $zip
        foreach($item in @($Manifest.storageObjects)){
            $entry=$entries[[string]$item.archivePath]
            if(-not $entry -or $entry.Length -ne [long]$item.bytes -or $entry.Length -gt 20971520){throw 'A mapped image has an unexpected size.'}
            $buffer=New-Object IO.MemoryStream
            try{$stream=$entry.Open();try{$stream.CopyTo($buffer)}finally{$stream.Dispose()};$bytes=$buffer.ToArray()}finally{$buffer.Dispose()}
            $encoded=Get-DrillEncodedObjectPath ([string]$item.bucket) ([string]$item.key)
            $type=[string]$item.remoteMetadata.mimetype
            if($type -cnotmatch '^image/(?:jpeg|png|webp|gif|svg\+xml)$'){
                $mimeMap=@{'.jpg'='image/jpeg';'.jpeg'='image/jpeg';'.png'='image/png';'.webp'='image/webp';'.gif'='image/gif'}
                $ext=[IO.Path]::GetExtension([string]$item.key).ToLowerInvariant()
                $type='application/octet-stream';if($mimeMap.ContainsKey($ext)){$type=$mimeMap[$ext]}
            }
            $headers=@{apikey=$Keys.Service;Authorization=('Bearer '+$Keys.Service);'x-upsert'='true'}
            $response=Invoke-DrillHTTP ('http://127.0.0.1:54321/storage/v1/object/'+$encoded) 'POST' $headers $bytes $type
            if($response.Status -notin @(200,201)){throw 'A local image upload did not succeed.'}
            $back=Invoke-DrillHTTP ('http://127.0.0.1:54321/storage/v1/object/authenticated/'+$encoded) 'GET' @{apikey=$Keys.Service;Authorization=('Bearer '+$Keys.Service)}
            if($back.Status -ne 200){throw 'A restored local image could not be read back.'}
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$actual=[BitConverter]::ToString($sha.ComputeHash($back.Bytes)).Replace('-','')}finally{$sha.Dispose()}
            if($actual -ine [string]$item.sha256){throw 'A restored image differs from the archive checksum.'}
            $checked++
        }
    } finally {$zip.Dispose()}
    return $checked
}
function Restore-DrillWebFiles([string]$SourceZip,[string]$WebRoot,[string]$AnonKey,[string]$PackageRoot) {
    if($AnonKey -cnotmatch '^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$'){throw 'Unexpected local browser credential format.'}
    if(-not (Test-Path -LiteralPath $WebRoot)){$null=New-Item -ItemType Directory -Path $WebRoot}
    $archive=[IO.Compression.ZipFile]::OpenRead($SourceZip)
    try{
        $entries=Get-StrokedZipFileEntries $archive
        foreach($name in $entries.Keys){
            if($name -cnotmatch '^(?:[a-zA-Z0-9_-]+\.(?:html|png|jpg|webp|ico)|assets/[a-zA-Z0-9_./-]+\.(?:js|css|png|jpg|jpeg|webp|gif|svg|woff|woff2))$'){continue}
            $target=Join-Path $WebRoot ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))
            $parent=Split-Path $target
            if(-not (Test-Path -LiteralPath $parent)){$null=New-Item -ItemType Directory -Path $parent -Force}
            if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Force}
            Copy-StrokedZipEntry $entries[$name] $target
        }
    }finally{$archive.Dispose()}
    $index=Join-Path $WebRoot 'index.html'
    $config=Join-Path $WebRoot 'assets\stroked-config.js'
    if(-not (Test-Path -LiteralPath $index) -or -not (Test-Path -LiteralPath $config)){throw 'Archived site entrypoint/configuration is missing.'}
    $utf8=New-Object Text.UTF8Encoding($false)
    $settings=[ordered]@{url='http://127.0.0.1:54321';publishableKey=$AnonKey;rpcPrefix='stroked_live_v55_';testing=$false;authCaptchaSiteKey=''}
    [IO.File]::WriteAllText($config,('window.STROKED_CONFIG=Object.freeze('+($settings|ConvertTo-Json -Compress)+');'),$utf8)
    [IO.File]::WriteAllText((Join-Path $WebRoot 'assets\stroked-payments-config.js'),"window.STROKED_PAYMENTS_CONFIG=Object.freeze({support:Object.freeze({environment:'testing',paymentLink:'',taxConfirmed:false,webhookVerified:false})});",$utf8)
    $vendor=Join-Path $WebRoot 'vendor';$null=New-Item -ItemType Directory -Path $vendor -Force
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'vendor\supabase.min.js') -Destination (Join-Path $vendor 'supabase.min.js') -Force
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'drill-client.js') -Destination (Join-Path $WebRoot 'drill-client.js') -Force
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'recovery-check.html') -Destination (Join-Path $WebRoot 'recovery-check.html') -Force
    $rx=New-Object Text.RegularExpressions.Regex('https://cdn\.jsdelivr\.net/npm/@supabase/supabase-js@[^"''<>\s]+')
    $sdkReplaced=0
    foreach($file in @(Get-ChildItem -LiteralPath $WebRoot -File -Filter '*.html')){
        $html=[IO.File]::ReadAllText($file.FullName)
        $sdkReplaced+=$rx.Matches($html).Count
        $html=$rx.Replace($html,'/vendor/supabase.min.js')
        $html=[regex]::Replace($html,'(?i)<meta name="robots" content="[^"]*">','<meta name="robots" content="noindex, nofollow">')
        if($html -match '(?i)<head>'){$html=[regex]::Replace($html,'(?i)<head>','<head><script src="/drill-runtime.js"></script><script src="/drill-client.js"></script>',1)}
        [IO.File]::WriteAllText($file.FullName,$html,$utf8)
    }
    if($sdkReplaced -lt 1){throw 'The expected archived browser client reference was not found.'}
    [IO.File]::WriteAllText((Join-Path $WebRoot 'robots.txt'),"User-agent: *`nDisallow: /`n",$utf8)
}
function New-DrillPassword {
    $bytes=New-Object byte[] 32;$random=[Security.Cryptography.RandomNumberGenerator]::Create()
    try{$random.GetBytes($bytes)}finally{$random.Dispose()}
    return 'Aa9!'+[Convert]::ToBase64String($bytes)
}
function New-DrillTestUsers($Keys) {
    $suffix=[Guid]::NewGuid().ToString('N')
    $state=[ordered]@{ConfirmID=$null;ResetID=$null;ConfirmEmail=('confirm-'+$suffix+'@recovery.invalid');ResetEmail=('reset-'+$suffix+'@recovery.invalid');NewPassword=(New-DrillPassword);MessageIDs=(New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal))}
    $script:ActiveTestState=$state
    $signup=Invoke-DrillHTTP 'http://127.0.0.1:54321/auth/v1/signup?redirect_to=http%3A%2F%2F127.0.0.1%3A3000%2F%3Fauth%3Dconfirm' 'POST' @{apikey=$Keys.Anon} (ConvertTo-DrillJSONBytes @{email=$state.ConfirmEmail;password=(New-DrillPassword);data=@{first_name='Recovery';last_name='Check';account_type='rider'}})
    if($signup.Status -ne 200){throw 'Local confirmation test signup failed.'}
    $user=$signup.Text|ConvertFrom-Json
    if($user.user){$user=$user.user}
    if([string]$user.id -cnotmatch '^[a-f0-9-]{36}$' -or $user.email_confirmed_at){throw 'The confirmation test account did not require confirmation.'}
    $state.ConfirmID=[string]$user.id
    # Only this synthetic local reset identity is pre-confirmed; restored users/MFA are untouched.
    $create=Invoke-DrillHTTP 'http://127.0.0.1:54321/auth/v1/admin/users' 'POST' @{apikey=$Keys.Service;Authorization=('Bearer '+$Keys.Service)} (ConvertTo-DrillJSONBytes @{email=$state.ResetEmail;password=(New-DrillPassword);email_confirm=$true;user_metadata=@{first_name='Recovery';last_name='Reset';account_type='rider'}})
    if($create.Status -notin @(200,201)){throw 'Local reset test identity creation failed.'}
    $reset=$create.Text|ConvertFrom-Json
    if($reset.user){$reset=$reset.user}
    if([string]$reset.id -cnotmatch '^[a-f0-9-]{36}$'){throw 'Local test identity did not return a valid identifier.'}
    $state.ResetID=[string]$reset.id
    return $state
}
function Read-DrillMailLink($Test,[string]$Email,[string]$Kind) {
    for($attempt=0;$attempt -lt 15;$attempt++){
        $list=Invoke-DrillHTTP 'http://127.0.0.1:54324/api/v1/messages?limit=50'
        if($list.Status -ne 200){throw 'Local test mailbox API is unavailable.'}
        $messages=$list.Text | ConvertFrom-Json
        foreach($message in @($messages.messages)){
            if(@($message.To | Where-Object {$_.Address -ceq $Email}).Count -lt 1){continue}
            if([string]$message.ID -cnotmatch '^[a-zA-Z0-9_-]{1,100}$'){throw 'Unexpected local mailbox identifier.'}
            $full=Invoke-DrillHTTP ('http://127.0.0.1:54324/api/v1/message/'+[string]$message.ID)
            if($full.Status -ne 200){continue}
            $body=$full.Text | ConvertFrom-Json
            $text=[Net.WebUtility]::HtmlDecode(([string]$body.HTML+' '+[string]$body.Text))
            foreach($match in [regex]::Matches($text,'https?://[^\s"''<>]+')){
                $uri=$null
                if(-not [Uri]::TryCreate($match.Value,[UriKind]::Absolute,[ref]$uri)){continue}
                if($uri.Scheme -cne 'http' -or $uri.Host -cne '127.0.0.1' -or $uri.Port -ne 54321 -or $uri.AbsolutePath -cne '/auth/v1/verify' -or $uri.UserInfo){continue}
                $query=@{};foreach($pair in $uri.Query.TrimStart('?').Split('&')){$parts=$pair.Split('=',2);if($parts.Length -eq 2){$query[[Uri]::UnescapeDataString($parts[0])]=[Uri]::UnescapeDataString($parts[1])}}
                if($query.type -cne $Kind -and -not ($Kind -ceq 'signup' -and $query.type -ceq 'email')){continue}
                $redirect=[Uri]([string]$query.redirect_to)
                if($redirect.Scheme -cne 'http' -or $redirect.Host -cne '127.0.0.1' -or $redirect.Port -ne 3000 -or $redirect.UserInfo){throw 'Test email contains an unexpected redirect.'}
                $null=$Test.MessageIDs.Add([string]$message.ID)
                return $uri.AbsoluteUri
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'Expected confirmation or reset message was not found in the local mailbox.'
}
function Remove-DrillTestUsers($Test,$Keys) {
    foreach($pair in @(@($Test.ConfirmID,$Test.ConfirmEmail),@($Test.ResetID,$Test.ResetEmail))){
        $id=[string]$pair[0];$email=[string]$pair[1]
        if(-not $id){continue}
        if($id -cnotmatch '^[a-f0-9-]{36}$' -or $email -cnotmatch '^(?:confirm|reset)-[a-f0-9]{32}@recovery\.invalid$'){throw 'Synthetic identity cleanup guard failed.'}
        $uri='http://127.0.0.1:54321/auth/v1/admin/users/'+$id
        $found=Invoke-DrillHTTP $uri 'GET' @{apikey=$Keys.Service;Authorization=('Bearer '+$Keys.Service)}
        if($found.Status -eq 404){continue}
        if($found.Status -ne 200){throw 'Synthetic identity cleanup lookup failed.'}
        $user=$found.Text|ConvertFrom-Json;if($user.user){$user=$user.user}
        if([string]$user.id -cne $id -or [string]$user.email -cne $email){throw 'Synthetic identity cleanup refused a different user.'}
        $result=Invoke-DrillHTTP $uri 'DELETE' @{apikey=$Keys.Service;Authorization=('Bearer '+$Keys.Service)}
        if($result.Status -notin @(200,204,404)){throw 'Synthetic local identity cleanup failed.'}
    }
    $list=Invoke-DrillHTTP 'http://127.0.0.1:54324/api/v1/messages?limit=100'
    if($list.Status -eq 200){
        $all=$list.Text|ConvertFrom-Json
        foreach($message in @($all.messages)){
            if(@($message.To | Where-Object {$_.Address -cin @($Test.ConfirmEmail,$Test.ResetEmail)}).Count){
                if([string]$message.ID -cmatch '^[a-zA-Z0-9_-]{1,100}$'){$null=$Test.MessageIDs.Add([string]$message.ID)}
            }
        }
    }
    if($Test.MessageIDs.Count){
        $result=Invoke-DrillHTTP 'http://127.0.0.1:54324/api/v1/messages' 'DELETE' @{} (ConvertTo-DrillJSONBytes @{IDs=@($Test.MessageIDs)})
        if($result.Status -ne 200){throw 'Synthetic local mailbox cleanup failed.'}
    }
}

function Wait-DrillStorage($Keys) {
    for($i=0;$i -lt 30;$i++){
        try{$r=Invoke-DrillHTTP 'http://127.0.0.1:54321/storage/v1/bucket' 'GET' @{apikey=$Keys.Service;Authorization=('Bearer '+$Keys.Service)};if($r.Status -eq 200){return}}catch{}
        Start-Sleep -Milliseconds 500
    }
    throw 'Local Storage API did not become ready.'
}
