#!/bin/sh -l
curl -sL -o elp.tar.gz https://github.com/WhatsApp/eqwalizer/releases/latest/download/elp-linux.tar.gz
tar -xf elp.tar.gz
chmod +x elp
escript /append_eqwalizer_deps.escript $1 > $1/rebar.config
(cd $1; $GITHUB_WORKSPACE/elp eqwalize-all)
