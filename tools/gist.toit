// Copyright (C) 2023 Toitware ApS.
// Use of this from code is governed by an MIT-style license that can be
// found in the LICENSE_MIT file.

import certificate-roots
import cli
import encoding.json
import http
import host.file
import net

GIST-URL-PREFIX_ ::= "https://gist.github.com/"
GIST-API_ ::= "https://api.github.com/gists"

download --output/string --gist-url/string --ui/cli.Ui:
  if not gist-url.starts-with GIST-URL-PREFIX_:
    ui.print "Invalid gist url: $gist-url"
    ui.abort

  // Extract the gist id from the url.
  gist-id := (gist-url.split "/").last

  with-http-client: | client/http.Client |
    headers := http.Headers
    headers.add "User-Agent" "toit-gist"
    response := client.get --uri="$GIST-API_/$gist-id" --headers=headers

    if response.status-code != 200:
      ui.print "Failed to download gist: $gist-url"
      ui.print "Status code: $response.status-code"
      body := #[]
      while chunk := response.body.read:
        body += chunk
      ui.print "Response: $body.to-string-non-throwing"
      ui.abort

    gist := json.decode-stream response.body
    files := gist["files"]
    files.do: | _ file/Map |
      outpath := "$output/$file["filename"]"
      download-file_ file["raw_url"] --to=outpath --ui=ui

download-file_ url/string --to/string --ui/cli.Ui:
  with-http-client: | client/http.Client |
    response := client.get --uri=url

    if response.status-code != 200:
      ui.print "Failed to download file: $url"
      ui.print "Status code: $response.status-code"
      body := #[]
      while chunk := response.body.read:
        body += chunk
      ui.print "Response: $body.to-string-non-throwing"
      ui.abort

    data := #[]
    while chunk := response.body.read:
      data += chunk

    file.write-content data --path=to

with-http-client [block]:
  network := net.open
  client := http.Client.tls network
      --root-certificates=certificate-roots.ALL
  try:
    block.call client
  finally:
    client.close
    network.close
