#!/bin/bash
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
set -e

# If kli not installed
if ! command -v kli &> /dev/null
then
    python3.13 -m venv .venv
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install -r requirements.txt
fi

random_suffix=$(openssl rand -base64 8 | tr -dc '[:alnum:]' | fold -w 8 | head -n 1)

### Configure witness and schemas
witness_url=${WITNESS_URL:-"http://localhost:5642"}
witness_aid=$(curl -s -D - -o /dev/null "$witness_url/oobi" | grep Keri-Aid | cut -d ' ' -f 2 | tr -d '\r')
keri_dir="$HOME/.keri" # TODO: If the user has access to /usr/local/var/keri/, that will be used by KERI instead
mkdir -p "$keri_dir/cf"
config_file="config_$random_suffix"

cat << EOF > "$keri_dir/cf/$config_file.json"
{
  "dt": "$(kli time)",
  "iurls": ["$witness_url/oobi/$witness_aid"]
}
EOF

### Create AID for LAR 1

lar1_name="lar1_${random_suffix}"
kli init --name "$lar1_name" --config-file "$config_file" --nopasscode
kli incept --name "$lar1_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias lar1 --toad 1
kli ends add  --name "$lar1_name" --alias lar1 --role mailbox --eid "$witness_aid"

lar1_aid=$(kli aid --name "$lar1_name" --alias lar1)
lar1_oobi=$(kli oobi generate --name "$lar1_name" --alias lar1 --role witness | tail -n 1)

### Create AID for LAR 2

lar2_name="lar2_${random_suffix}"
kli init --name "$lar2_name" --config-file "$config_file" --nopasscode
kli incept --name "$lar2_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias lar2 --toad 1
kli ends add  --name "$lar2_name" --alias lar2 --role mailbox --eid "$witness_aid"

lar2_aid=$(kli aid --name "$lar2_name" --alias lar2)
lar2_oobi=$(kli oobi generate --name "$lar2_name" --alias lar2 --role witness | tail -n 1)

### Introduction of wallets

kli oobi resolve --name "$lar1_name" --oobi "$lar2_oobi" --oobi-alias lar2
kli oobi resolve --name "$lar2_name" --oobi "$lar1_oobi" --oobi-alias lar1

### Create multisig aid from LAR1 and LAR2

group_config_file=$(mktemp)
cat << EOF > "$group_config_file"
{
  "transferable": true,
  "wits": ["$witness_aid"],
  "aids": ["$lar1_aid", "$lar2_aid"],
  "toad": 1,
  "isith": "2",
  "nsith": "2"
}
EOF

kli multisig incept --name "$lar1_name" --alias lar1 --group acme --file "$group_config_file" &
pid+=("$!")

kli multisig incept --name "$lar2_name" --alias lar2 --group acme --file "$group_config_file" &
pid+=("$!")

wait "${pid[@]}"

echo ""
echo "Success creating Legal Entity AID"
echo ""
echo "Check status by using one of the following commands:"
echo ""
echo "kli status --name $lar1_name --alias acme"
echo "kli status --name $lar2_name --alias acme"
echo ""
echo "To check for IPEX messages, use the following command:"
echo ""
echo "kli ipex list --name $lar1_name --alias acme --poll"
