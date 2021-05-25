# Table des matières

1. [Certificats Openshift](#Certificat Openshift)
   1. [Certificat Ingress](#Certificat-Ingress)
   2. [Certificat API](#Certificat-API)

# Certificat Openshift

## Certificat Ingress

Les certificats de l'operateur Ingress est autosigné lors de l'installation, elle est possible être changée en modifiant la ressource `ingress.controller`.

Certain prérequis sont a respecté pour le certificat:

- `Subject Alternative Name` doit être un `wildcard` comme ceci: `*.apps.<cluster>.<domain>`
- Le certificat et la clef doit être sous format PEM et non chiffré
- Le certificat du server doit être en premier suivis les autorité intermédiaire puis terminant par l'autorité de certification racine.
- Copier la CA root dans un fichier additionnel.

Pour vérifier si votre certificat est valide:

```shell
openssl x509 -in <fichier cert>.crt -noout -text
```

Si la valeur décrite par `X509v3 Subject Alternative Name` ne contient pas de `wildcard`, il faudra resigner le certificat.

Il faudra créer un `configMap` qui inclut uniquement le certificat `root CA` utilisé pour signer le certificat `wildcard`:

```shell
oc create configmap custom-ca \
     --from-file=ca-bundle.crt=</chemin/vers/exemple-ca.crt> \
     -n openshift-config
```

Puis mettre à jour la configuration du proxy à l'échelle du cluster avec le `configMap` nouvellement créée :

```shell
 oc patch proxy/cluster \
     --type=merge \
     --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'
```

Ensuite déposer un secret sous le projet `openshift-ingress` avec les clef et certificat signé par l'autorité:

```shell
oc create secret tls <secret> \
     --cert=</chemin/vers/cert.crt> \
     --key=</chemin/vers/cert.key> \
     -n openshift-ingress
```

Puis modifier le contrôleur Ingress pour utiliser le nouveau secret tls:

```shell
oc patch ingresscontroller.operator default \
     --type=merge -p \
     '{"spec":{"defaultCertificate": {"name": "<secret>"}}}' \
     -n openshift-ingress-operator
```

NOTE: Cette étape peut prendre un peu de temps avant que la modification soit propager sur le cluster.

## Certificat API

Ce certificat par défaut est signé par la CA du cluster, cependant il est possible de la changer par un certificat signé par une autorité de confiance. 

NOTE: Il n'est pas recommandé de modifier le certificat du domaine `api-int.<cluster>.<domaine>`, cela peut rendre le cluster instable.

Certains prérequis sont à respecté pour le certificat:

- `Subject Alternative Name` doit avoir le fqdn du serveur `API` (`api.<cluster>.<domane>`)
- Le certificat et la clef doit être sous format PEM et non chiffré
- Le certificat du serveur doit être en premier suivis les autorité intermédiaire puis terminant par l'autorité de certification racine.

Pour modifier le certificat de l'API, il faut créer un secret `TLS` sous le projet `openshift-config` en utilisant la commande suivante:

```shell
oc create secret tls <secret> \
     --cert=</chemin/vers/cert.crt> \
     --key=</chemin/vers/cert.key> \
     -n openshift-config
```

Une fois le secret créer, il faut modifier le serveur API pour qu'il référence le secret:

```shell
oc patch apiserver cluster \
     --type=merge -p \
     '{"spec":{"servingCerts": {"namedCertificates":
     [{"names": ["api.<cluster>.<domaine>"], 
     "servingCertificate": {"name": "<secret>"}}]}}}'
```

Il est possible de vérifier si le changement a bien été prise en compte a l'aide de la commande:

```shell
oc get apiserver cluster -o yaml
```

Exemple de sortie:

```yaml
...
spec:
  servingCerts:
    namedCertificates:
    - names:
      - api.<cluster>.<domaine>
      servingCertificate:
        name: <secret>
...
```

