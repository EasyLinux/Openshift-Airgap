# Table des matières 
1. [Catalogue Openshift](#Catalogue-Openshift)
   1. [Construction du catalogue](#Construction-du-catalogue)
   2. [Registre Miroir](#Registre-miroir)
   3. [Désactiver le catalogue d'usine](#Désactiver-le-catalogue-d'usine)
   4. [Configurer les pull-secret](#Configurer-les-pull-secret)
   5. [Appliquer le manifeste imagecontentsourcepolicy](#Appliquer-le-manifeste-imagecontentsourcepolicy)
   6. [Ajouter le catalogue personnalisé](#Ajouter-le-catalogue-personnalisé)
   7. [Registre déconnecté/Accès non directe](#Registre-déconnecté/Accès-non-directe)
2. [Cluster Logging](#Cluster-Logging)
   1. [Installer ElasticSearch](#Installer-ElasticSearch)
   2. [Installer ClusterLogging](#Installer-ClusterLogging)
   3. [Deployer l'instance ClusterLogging](#Deployer-l'instance-ClusterLogging)

# Catalogue Openshift

Les catalogues Openshift n'étant pas disponible sur un cluster déconnecté, il est nécessaire de construire le catalogue, de télécharger les images sur internet et de les pousser sur un registre local.

## Construction du catalogue

Pour construire le catalogue, il est nécessaire de s'assurer que la machine qui exécute la commande a accès à internet et au registre cible. Cette étape ne nécessite pas de connexion à Openshift. (Les pull-secret Openshift peut être utiliser dans cette étape).

La commande ci-dessous doit être lancée sur l'hôte avec un accès internet:

```shell
REG_CREDS=$XDG_RUNTIME_DIR/containers/auth.json;
oc adm catalog build --appregistry-org redhat-operators \
	--from=registry.redhat.io/openshift4/ose-operator-registry:v4.5 \
	--filter-by-os="<os>/<arch>" --to=<registre url>/olm/redhat-operators:v1 
	-a ${REG_CREDS} 
	[--insecure]
```

Exemple de sortie

```shell
INFO[0013] loading Bundles                               dir=/var/folders/st/9cskxqs53ll3wdn434vw4cd80000gn/T/300666084/manifests- 829192605
...
Pushed sha256:f73d42950021f9240389f99ddc5b0c7f1b533c054ba344654ff1edaf6bf827e3 to example_registry:5000/olm/redhat-operators:v1
```

Exemple d'erreur

```shell
...
INFO[0014] directory                                     dir=/var/folders/st/9cskxqs53ll3wdn434vw4cd80000gn/T/300666084/manifests-829192605 file=4.2 load=package
W1114 19:42:37.876180   34665 builder.go:141] error building database: error loading package into db: fuse-camel-k-operator.v7.5.0 specifies replacement that couldn't be found
Uploading ... 244.9kB/s
```

## Registre Miroir

La commande `oc adm catalog mirror` permet de télécharger et de pousser les images sur le registre miroir.
Il est cependant possible de créer seulement un manifeste et de repousser cette étape ultérieurement en utilisant l'option `--manifest-only`.

```
oc adm catalog mirror \
    <nom_hote_du_registre>:<port>/olm/redhat-operators:v1 \
    <nom_hote_du_registre>:<port>/<namespace> \
    [-a ${REG_CREDS}] \
    [--insecure] \
    --filter-by-os='.*' \
    [--manifests-only] 
```

## Désactiver le catalogue d'usine

Cette étape est nécessaire pour désactiver les catalogues d'usine fournit à l'installation.

```
oc patch OperatorHub cluster --type json \
    -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
```

## Configurer les pull-secret

Si le registre miroir a besoin d'une authentification pour pouvoir télécharger les images, il faudra configurer les pulls secrets de manière globale dans le projet openshift-config et mettre à jour le secret pull-secret de la manière suivante:

```shell
oc extract --to=- secret/pull-secret -n openshift-config | jq -r > pull-secret-jq.txt
```

Cette commande extraira le secret dans un fichier appeler `pull-secret-jq.txt` de maniere formatté.<br/>Il faudra encoder le login, mot de passe en base64 sous le format `<login>:<mot_de_passe>` puis ajouter une entrée dans le fichier pull-secret-jq.txt.

Exemple d'entrée:

```json
{
   "auths":{
      "<nom_d'hote_du_registre>:<port>": {
          "auth": "<login:motdepasse encodé en base64>"
      },
      "cloud.openshift.com": {
         "auth":"b3Blb=",
         "email":"you@example.com"
      },
      "quay.io": {
         "auth":"b3Blb=",
         "email":"you@example.com"
      }
   }
}
```

Ensuite, il suffira de mettre à jour le secret à l'aide des commandes suivantes:

```shell
tr -d '\n\r\t ' <pull-secret-jq.txt >pull-secret.txt
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret.txt
```

Attention, cette étape peut rendre momentanément indisponible le cluster pendant que ce secret se propage sur les noeuds.

## Appliquer le manifeste imageContentSourcePolicy

Lors de l'exécution de la commande `oc adm catalog mirror`, un dossier a été créé sur le répertoire courant dans laquelle contient la localisation des images distantes sur le miroir. Si l'option `--manifest-only` a été utilisée lors de l'exécution, et que seul quelques images sont nécessaires, il faudra trier dans le fichier `mapping.txt` les images souhaitées.

La commande ci-dessous fera l'étape de télécharger les images et de les pousser sur le registre miroir en utilisant le fichier `mapping.txt`

```shell
oc image mirror \
    [-a ${REG_CREDS}] \
    --filter-by-os='.*' \
    -f ./redhat-operators-manifests/mapping.txt
```

Pour appliquer le manifeste, il suffit d'utiliser la commande `oc create -f imageContentSourcePolicy.yaml`.

## Ajouter le catalogue personnalisé

Pour déployer le catalogue Openshift personnalisé, il faut créer une ressource de type `CatalogSource` puis l'appliquer dans le projet `openshift-marketplace` .

Modifier le yaml suivant pour qu'il corresponde aux specifications:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-operator-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: <registry_host_name>:<port>/olm/redhat-operators:v1 
  displayName: My Operator Catalog
  publisher: grpc
```

Créer la ressource à l'aide de la commande `oc create -f catalogsource.yaml` et vérifier son état avec `oc get pods -n openshift-marketplace`.

## Registre déconnecté/Accès non directe

Dans le cas où l'accès au registre miroir est impossible, il est possible d'utiliser le fichier `mapping.txt` directement pour télécharger les images sur un hôte avec un acces internet puis les pousser directement avec un autre hôte qui a acces au registre miroir à l'aide de la commande `skopeo`.

Voici un script typique sur la manipulation du fichier mapping.txt pour télécharger toutes ses images localement. Ce script est à utiliser avec un hôte qui a accès à internet.

```shell
for image in `sed -re 's/=[a-z0-9:\/.-]*\//=/g' mapping.txt`; do 
	src=${image#=*}
	dst=${image#*=}
	skopeo copy --all [--authfile ${REG_CREDS}] docker://${src} oci-archive:${dst}
	mv ${dst#*:} ${dst}.tar.gz 
done
```

Une fois le contenu transféré sur l'hote avec un accès sur le registre miroir, il suffit de pousser l'image avec `skopeo`.

```shell
for image in `ls -1`; do 
	skopeo copy --all [--authfile ${REG_CREDS}] oci-archive:${image} docker://<registre_miroir>:<port>/<namespace>/${image}
done
```

# Cluster Logging

Pour pouvoir installer l'opérateur Cluster Logging sur un cluster déconnecté, il faut avoir configuré le catalogue au préalable et installer l'opérateur ElasticSearch à l'aide de ce même catalogue.

## Installer ElasticSearch

Créer un projet sous le nom `openshift-operators-redhat` pour l'opérateur ElasticSearch.<br/>La ressource ci-dessous peut être utilisée pour créer le projet avec la commande `oc create -f <nom_du_fichier.yaml> `

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators-redhat 
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
```

Créer la ressource `OperatorGroup` puis appliquer avec la commande `oc create -f <nom du fichier yaml>`.

```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-operators-redhat
  namespace: openshift-operators-redhat 
spec: {}
```

Faire de la même manière avec la ressource `Subscription`.

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: "elasticsearch-operator"
  namespace: "openshift-operators-redhat" 
spec:
  channel: "4.5" 
  installPlanApproval: "Automatic"
  source: "<nom du catalogue>" 
  sourceNamespace: "openshift-marketplace"
  name: "elasticsearch-operator"
```

## Installer ClusterLogging

Créer un projet sous le nom `openshift-logging` pour l'opérateur ClusterLogging.<br/>La ressource ci-dessous peut être utilisée pour créer le projet avec la commande `oc create -f <nom_du_fichier.yaml> `

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators-redhat 
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
```

Créer la ressource `OperatorGroup` puis appliquer avec la commande `oc create -f <nom du fichier yaml>`.

```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-logging
  namespace: openshift-logging 
spec:
  targetNamespaces:
  - openshift-logging
```

Faire de la même manière avec la ressource `Subscription`.

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging 
spec:
  channel: "4.5" 
  name: cluster-logging
  source: <nom du catalogue>
  sourceNamespace: openshift-marketplace
```

## Deployer l'instance ClusterLogging

Pour déployer une instance `ClusterLogging`,il faut utiliser la ressource ci-dessous. Cette ressource va solliciter l'opérateur `ClusterLogging`, qui va s'occuper de créer les déploiements et configuration de l'opérateur `ElasticSearch`.

Pour que l'instance soit persistante, il faudra changer la valeur `storageClassName`, ou supprimer la partie `spec.logsStore.elasticsearch.storage` pour que le stockage soit éphémère.

```yaml
apiVersion: "logging.openshift.io/v1"
kind: "ClusterLogging"
metadata:
  name: "instance" 
  namespace: "openshift-logging"
spec:
  managementState: "Managed"  
  logStore:
    type: "elasticsearch"  
    retentionPolicy: 
      application:
        maxAge: 1d
      infra:
        maxAge: 7d
      audit:
        maxAge: 7d
    elasticsearch:
      nodeCount: 3 
      storage:
        storageClassName: "<storage-class-name>" 
        size: 200G
      resources: 
        requests:
          memory: "8Gi"
      proxy: 
        resources:
          limits:
            memory: 256Mi
          requests:
             memory: 256Mi
      redundancyPolicy: "SingleRedundancy"
  visualization:
    type: "kibana"  
    kibana:
      replicas: 1
  curation:
    type: "curator"
    curator:
      schedule: "30 3 * * *" 
  collection:
    logs:
      type: "fluentd"  
      fluentd: {}
```

Vérifier que l'instance a bien été installée à l'aide de la commande `oc get pods -n openshift-logging`

Exemple de sortie

```shell
NAME                                            READY   STATUS      RESTARTS   AGE
cluster-logging-operator-749c8bcddf-d6z28       1/1     Running     0          3d12h
curator-1620358200-wzv6f                        0/1     Completed   0          5h25m
elasticsearch-cdm-u9ypyf41-1-74bfcd5f7-4bd7s    2/2     Running     0          25h
....
fluentd-x5h4v                                   1/1     Running     0          25h
kibana-75b6b87d87-d6kdp                         2/2     Running     0          25h
```

Pour plus d'information sur la configuration de la ressource, clicker [ici](https://docs.openshift.com/container-platform/4.5/logging/cluster-logging-deploying.html)
