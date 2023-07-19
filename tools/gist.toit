// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the tools/LICENSE file.

import certificate_roots
import cli
import encoding.json
import http
import host.file
import net

GIST_URL_PREFIX_ ::= "https://gist.github.com/"
GIST_API_ ::= "https://api.github.com/gists"

download --output/string --gist_url/string --ui/cli.Ui:
  if not gist_url.starts_with GIST_URL_PREFIX_:
    ui.print "Invalid gist url: $gist_url"
    ui.abort

  // Extract the gist id from the url.
  gist_id := (gist_url.split "/").last

  with_http_client: | client/http.Client |
    headers := http.Headers
    headers.add "User-Agent" "toit-gist"
    response := client.get --uri="$GIST_API_/$gist_id" --headers=headers

    if response.status_code != 200:
      ui.print "Failed to download gist: $gist_url"
      ui.print "Status code: $response.status_code"
      body := #[]
      while chunk := response.body.read:
        body += chunk
      ui.print "Response: $body.to_string_non_throwing"
      ui.abort

    gist := json.decode_stream response.body
    files := gist["files"]
    files.do: | _ file/Map |
      outpath := "$output/$file["filename"]"
      download_file_ file["raw_url"] --to=outpath --ui=ui

download_file_ url/string --to/string --ui/cli.Ui:
  with_http_client: | client/http.Client |
    response := client.get --uri=url

    if response.status_code != 200:
      ui.print "Failed to download file: $url"
      ui.print "Status code: $response.status_code"
      body := #[]
      while chunk := response.body.read:
        body += chunk
      ui.print "Response: $body.to_string_non_throwing"
      ui.abort

    data := #[]
    while chunk := response.body.read:
      data += chunk

    file.write_content data --path=to

with_http_client [block]:
  network := net.open
  client := http.Client.tls network
      --root_certificates=certificate_roots.ALL
  try:
    block.call client
  finally:
    client.close
    network.close
