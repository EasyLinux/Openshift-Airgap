# Tables des Matières

1. [Disaster Recovery](#Disaster-Recovery)
   1. [Sauvegarde](#Sauvegarde)
   2. [Restauration](#Restauration)

# Disaster Recovery

## Sauvegarde

Pour effectuer une sauvegarde, il faut s'assurer d'avoir soit un accès SSH au server `master` du cluster ou être `cluster-admin` et utiliser la commande `oc debug nodes/<master fqdn>`

Il existe un script existant sur les serveurs `master` qui permet la sauvegarde de l'ETCD. Pour faire la sauvegarde, il suffit d'exécuté le script ci-dessous:

```shell
/usr/local/bin/cluster-backup.sh <dossier du backup>
```

Ce script génère 2 fichier qui contient toutes les ressources du cluster (exclut les images).

## Restauration

Pour effectuer une restauration complète du cluster Openshift, il faut impérativement s'assurer d'avoir un accès SSH aux serveurs `master`. Les étapes qui suivent assument que les `sauvegardes` sont stockées dans le répertoire `/home/core/backup` et être en SSH sur tous les serveurs `master`.

Il faudra arrêter tous les pods statiques existant sur les nœuds `master` (il n'est pas nécessaire d'arrêter les pods sur le serveur choisi pour la restauration):

```shell
sudo mv /etc/kubernetes/manifests/etcd-pod.yaml /tmp
```

La commande suivante ne doit produire aucune sortie, s'il y a une sortie, attendre quelque minute et relancer la commande jusqu'à qu'il n'y a plus de sortie:

```shell
sudo crictl ps | grep etcd | grep -v operator
```

La même chose pour l'operateur `api-server`:

```shell
sudo mv /etc/kubernetes/manifests/kube-apiserver-pod.yaml /tmp
```

Vérifiez que la commande ne produit pas de sortie.

```shell
sudo crictl ps | grep kube-apiserver | grep -v operator
```

Déplacez les données `etcd` dans emplacement different:

```shell
sudo mv /var/lib/etcd/ /tmp
```

Faites de même pour chaque serveur `master`

Une fois tous les statiques pods statiques arrêtés, utiliser le serveur choisi pour la restauration et exécuter la commande suivante:

```shell
sudo -E /usr/local/bin/cluster-restore.sh /home/core/backup
```

Redémarrer sur tous les serveurs `master` le service `kubelet`:

```shell
sudo systemctl restart kubelet.service
```

Vérifier que le container `etcd` est en cours d'exécution:

```shell 
sudo crictl ps | grep etcd | grep -v operator
```

Vérifier que le pod `etcd` est en cours d'exécution:

```shell
oc get pods -n openshift-etcd | grep etcd
```

NOTE: Il est possible de recevoir cette erreur `Unable to connect to the server: EOF` lors de l'authentification, attendre quelque instant, et réessayer.

Une fois que le pod `etcd`est cours d'exécution, il est nécessaire de redémarrer les services `etcd`, `kubeapiserver`, `kubecontrollermanager` et `kubescheduler`

Pour redémarrer le service `etcd`:

```shell
oc patch etcd cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge 
```

Pour redémarrer le service `kubeapiserver`

```shell
oc patch kubeapiserver cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
```

Pour redémarrer le service `kubecontrollermanager`:

```shell
oc patch kubecontrollermanager cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
```

Pour redémarrer le service `kubescheduler`:

```shell
oc patch kubescheduler cluster -p='{"spec": {"forceRedeploymentReason": "recovery-'"$( date --rfc-3339=ns )"'"}}' --type=merge
```

Pour vérifier leurs états, remplacer `<resources>` par l'un des services:

```shell
oc get <resources> -o=jsonpath='{range .items[0].status.conditions[?(@.type=="NodeInstallerProgressing")]}{.reason}{"\n"}{.message}{"\n"}'
```

Exemple de sortie:

```shell
AllNodesAtLatestRevision
3 nodes are at revision 7
```

Si la sortie comprend plusieurs numéros de révision, tels que `2 nodes are at revision 6; 1 nodes are at revision 7`, cela signifie que la mise à jour est toujours en cours. Attendre quelque instant, et réessayer.
