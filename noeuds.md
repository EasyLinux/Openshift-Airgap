# Table des matières

1. [Travailler avec les nœuds](#Travailler-avec-les-nœuds)
     	1. [Ajouter des nœuds worker](#Ajouter-des-nœuds-worker)
      2. [Supprimer des nœuds worker](#Supprimer-des-nœuds-worker)

# Travailler avec les nœuds

## Ajouter des nœuds worker

Pour ajouter des nouveaux nœuds `worker` sur un cluster existant depuis plus de 24h, il faut utiliser le fichier `worker.ign` créé par `openshift-install` et remplacer le certificat.

Pour remplacer le certificat de manière "automatique":

```shell
MCS=api-int.<nom de domaine du cluster>:22623
jq -cr ".ignition.security.tls.certificateAuthorities[].source |= \"data:text/plain;charset=utf-8;base64,$(openssl s_client -showcerts -connect </dev/null  $MCS 2>/dev/null| openssl x509|base64 --wrap=0)\"" <worker.ign >worker-new.ign
```

Si le fichier `worker.ign` a été supprimer post-installation, utiliser cette commande pour le generer:

```shell
oc extract --to=worker.ign -n openshift-machine-api secret/worker-user-data
```

Puis utiliser ce même fichier pour initialiser la machine RHCOS. Lorsque la machine sera initialiser, il sera visible sous la commande `oc get nodes` en état `NotReady`.

Pour que le nœud soit en état `Ready`, il faut approuver le `csr` a l'aide de la commande `oc adm certificate approve <nom du noeud>`.

S'il existe plusieurs nœuds où le `csr` doit être approuver, utiliser le script ci-dessous pour automatiser:

```shell
oc get csr -o json | jq -r '.items[] | select(.status == {}) | .metadata.name' | xargs -n1 oc adm certificate approve
```

Pour initialiser un RHCOS, plus d'information peut ếtre trouvé [ici](https://docs.openshift.com/container-platform/4.5/installing/installing_bare_metal/installing-bare-metal.html#installation-user-infra-machines-iso_installing-bare-metal).

## Supprimer des nœuds worker

Pour supprimer des nœuds `worker`, il faut d'abord rendre le noeud non planifiable avec la commande `oc adm cordon <nom du noeud>`, puis s'assurer que la charge du nœuds soit déplacer sur les autres nœuds existant avec la commande `oc adm drain <nom du noeud>`.

Une fois ces étapes faites, il est désormais possible en toutes sécurité de supprimer le nœud sans avoir d'impact avec la commande `oc delete node <nom du noeud>`

Exemple de commandes:

```shell
oc adm cordon worker1.example.com
oc adm drain worker1.example.com
oc delete node worker1.example.com
```

Pour plus d'information, consulter la documentation [ici](https://docs.openshift.com/container-platform/4.5/nodes/nodes/nodes-nodes-working.html#nodes-nodes-working-deleting_nodes-nodes-working).