#!/bin/bash
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
set -e

# If kli not installed
if ! command -v kli &> /dev/null
then
    python3.13 -m venv .venv
    source .venv/bin/activate
    pip install keri==1.2.6
fi


random_suffix=$(openssl rand -base64 8 | tr -dc '[:alnum:]' | fold -w 8 | head -n 1)
geda_name="geda_${random_suffix}"
qvi_name="qvi_${random_suffix}"

witness_url=${WITNESS_URL:-"http://localhost:5642"}
witness_aid=$(curl -s -D - -o /dev/null "$witness_url/oobi" | grep Keri-Aid | cut -d ' ' -f 2 | tr -d '\r')

### Create Gleif External AID
kli init --name "$geda_name" --nopasscode

kli oobi resolve --name "$geda_name" --oobi "$witness_url/oobi/$witness_aid"
kli incept --name "$geda_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias geda --toad 1
kli ends add  --name "$geda_name" --alias geda --role mailbox --eid "$witness_aid"


geda_oobi=$(kli oobi generate --name "$geda_name" --alias geda --role witness | tail -n 1)
geda_aid=$(kli aid --name "$geda_name" --alias geda)

### Create QVI
kli init --name "$qvi_name" --nopasscode
kli oobi resolve --name "$qvi_name" --oobi "$witness_url/oobi/$witness_aid"
kli incept --name "$qvi_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias qvi_proxy --toad 1


kli oobi resolve --name "$qvi_name" --oobi "$geda_oobi"
kli incept --name "$qvi_name" --wit "$witness_aid" --icount 1 --ncount 1 --isith 1 --nsith 1 --transferable --alias qvi --toad 1 --delpre "$geda_aid" --proxy qvi_proxy &
pids+=($!)

kli delegate confirm --name "$geda_name" --auto --alias geda  

wait $pids

kli ends add  --name "$qvi_name" --alias qvi --role mailbox --eid "$witness_aid"

qvi_oobi=$(kli oobi generate --name "$qvi_name" --alias qvi --role witness | tail -n 1)
qvi_aid=$(kli aid --name "$qvi_name" --alias qvi)



### Credentials

schema_qvi_said="EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao" # QVI credential schema

kli oobi resolve --name "$geda_name" --oobi "$qvi_oobi"

kli vc registry incept --name "$geda_name" --alias geda --registry-name vlei

LEI="123"
kli oobi resolve --name "$geda_name" --oobi "https://portal.globalvlei.com/oobi/$schema_qvi_said"
kli oobi resolve --name "$qvi_name" --oobi "https://portal.globalvlei.com/oobi/$schema_qvi_said"
kli vc create --name "$geda_name" --alias geda --registry-name vlei --data "{\"LEI\": \"$LEI\"}" --schema "$schema_qvi_said" --recipient "$qvi_aid"

qvi_credential_said=$(kli vc list --name "$geda_name" --alias "geda" --schema "$schema_qvi_said" --issued --said)


kli ipex grant --name "$geda_name" --alias geda --recipient "$qvi_aid" --said "$qvi_credential_said"

kli ipex list --name "$qvi_name" --alias qvi --poll
grant_qvi_said=$(kli ipex list --name "$qvi_name" --alias qvi --type grant --said | tail -n 1)
kli ipex admit --name "$qvi_name" --alias qvi --said "$grant_qvi_said"
kli ipex list --name "$geda_name" --alias geda --poll