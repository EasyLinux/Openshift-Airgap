Tables des matieres
===================
1. [Centreon Openshift API](#Centreon-Openshift-API)
2. [Centreon Prometheus API](#Centreon-Prometheus-API)
3. [Annexes](#Annexes)

Il y a plusieurs maniere de surveiller un cluster Openshift, via Prometheus ou l'API de Kubernetes.

Centreon Openshift API
======================

Ce plugin de surveil de maniere general et basique l'infrastructure et les ressources d'Openshift.

Prerequis
---------

* Centreon 24.04
* Openshift

Installation
------------

**Centreon Plugin**

Installer le plugin sur chaque collecteur via la commande:

```bash
yum install centreon-plugin-Cloud-Kubernetes-Api -y
```

**Centreon Plugin Packs**

Via l'interface (Configuration > Pack de Plugin), installer le Packs de plugin `Kubernetes API`

**Openshift**

Il existe 2 maniere pour configurer ce Plugin, via la commande `kubectl` ou via l'API Rest d'Openshift.

Cette documentation ne couvrira que l'API Rest, pour plus d'information sur la maniere kubectl, visiter la documentation officiel du plugin pack [ici](https://docs.centreon.com/21.04/en/integrations/plugin-packs/procedures/cloud-kubernetes-api.html).

Pour utiliser l'API Rest d'Openshift, il faudra creer un compte de service (service account) et s'assurer que celui-ci a suffisament de droit pour surveiller l'etat du cluster Openshift.

Pour creer un compte de service Openshift, la commande suivante devra être executer:

```bash
oc create sa centreon-sa -n kube-system
```

Ensuite, jouer la commande suivante pour fabriquer le `ClusterRole` et établir la liaison avec le compte de service:

```bash
cat <<EOF ||
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: centreon-api-access
rules:
- apiGroups:
  - ""
  - apps
  - batch
  resources:
  - cronjobs
  - daemonsets
  - deployments
  - events
  - namespaces
  - nodes
  - persistentvolumes
  - pods
  - replicasets
  - replicationcontrollers
  - statefulsets
  verbs:
  - get
  - list
- apiGroups:
  - ""
  resources:
  - nodes/metrics
  - nodes/stats
  verbs:
  - get
- nonResourceURLs:
  - /metrics
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: centreon-api-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: centreon-api-access
subjects:
- kind: ServiceAccount
  name: centreon-sa
  namespace: kube-system
EOF
```

**Configuration du Plugin Pack**

Il faudra tout d'abord recuperer le token du compte de service en executant la commande suivante:

```bash
oc sa get-token centreon-sa -n kube-system
```

Ensuite, éxécuter les commande suivante pour configurer le `HOST` avec ses `MACCRO`:

```bash
centreon -u admin -p <mot de passe> -o HOST -a ADD  -v "<Nom de l'hôte>;<Alias de l'hôte>;<IP/DNS du hôte>;Cloud-Kubernetes-Api-custom;<Nom du Collecteur>;<Groupe du hôte>"
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;KUBERNETESAPIHOSTNAME;api.<FQDN du cluster>;0;API du cluster"
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;KUBERNETESAPIPORT;6443;0;port de l'API du cluster"
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;KUBERNETESAPITOKEN;<(oc sa get-token centreon-sa)>;1;compte de service du cluster"
##L'action ci-dessous depends seulement si votre cluster est signé par une authorité reconnu par votre Centreon
## Si elle n'est pas reconnu, il faudra l'executer.
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;EXTRAOPTIONS;--insecure;0;API du cluster"
```

Puis configurer les services a qui permettra de surveiller le cluster via l'API:

```bash
for service in `centreon -u admin -p <mot de passe> -o STPL -a show | grep Cloud-Kubernetes | grep -v custom | cut -d ';' -f 2`; do
centreon -u admin -p Pa55w.rd -o Service -a ADD -v "<Nom de l'hôte>;${service/Cloud-Kubernetes-/};${service}";
done
```

Une fois les commandes appliqué, exporter la configuration et recharger le Centreon Central. [Documentation ici](#Recharger-Centreon)

NOTE: Certain services peuvent avoir des faux positifs, il faudra reconfigurer les MACCRO `*CRITICAL*`.

Exemple: Pour Pod-Status-API, les MACCROs `CRITICALCONTAINERSTATUS` et `CRITICALPODSTATUS` devra avoir la valeur `%{status} !~ /running/i && %{status} !~ /terminated/i` et  `%{status} !~ /running/i && %{status} !~ /succeeded/i` respectivement.

Centreon Prometheus API
=======================

Prerequis
---------

* Centreon 24.04
* Openshift

Installation
------------

**Centreon Plugins**

```bash
yum install centreon-plugin-Cloud-Prometheus-Api
```

**Centreon Plugin Packs**

Via l'interface (Configuration > Pack de Plugin), installer le Packs de plugin `Prometheus Server`

**Openshift Prometheus**

Openshift nécessite un token API via lequel Prometheus va authentifier les requêtes, il est possible de reutilisé le token du compte de service `centreon-sa` créer pour l'API Rest d'Openshift

Si le besoin necessite un autre compte de service pour Prometheus, executer les commandes suivantes:

```bash
oc create sa -n kube-system centreon-prometheus-sa
oc adm policy add-cluster-role-to-user centreon-api-access -z centreon-prometheus-sa -n kube-system
```

Pour recuperer le token:
```bash
oc sa get-token centreon-prometheus-sa -n kube-system
```

**Configuration du Plugin Packs**

Il y a 2 mode avec ce Plugin, le mode `target-status` et `expression`, cette documentation decrira les 2 modes.

Le mode `target-status` permet de verifier le statut de tous les composants surveillés par Prometheus.

Le mode `expression` permet de faire une requete PromQL sur Prometheus et d'utiliser son resultat pour surveiller une metrique.

Pour les 2 modes, il faudra configurer l'hôte d'abord sur Centreon:

```bash
centreon -u admin -p <mot de passe> -o HOST -a ADD -v "<Nom de l'hôte>;<Alias de l'hôte>;<IP/DNS du hôte>;Cloud-Prometheus-Kubernetes-Api-custom;<Nom du Collecteur>;<Groupe du hôte>"
## Si pour le mode expression, des metriques applicatives sont voulues, utilisé la route Thanos.
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;PROMETHEUSAPIHOSTNAME;<Prometheus FQDN>;0;Prometheus hôte"
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;PROMETHEUSAPIPROTO;https;0;Protocole"
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;PROMETHEUSAPIPORT;443;0;Prometheus hôte"
## Si votre certificat n'est pas reconnu par Centreon, l'option `--insecure` devra être inclus
centreon -u admin -p <mot de passe> -o HOST -a SETMACRO -v "<Nom de l'hôte>;EXTRAOPTIONS;--header=\"Authorization: Bearer <Token du compte de service>\";0;Token Openshift"
```

**Target-status**

Si un filtre est necessaire, il vous faudra utiliser l'option `--filter-label=<attribut>,<valeur>`.

Pour connaitre les attributs et leur valuers, il suffit d'utiliser la commande suivante sur le Centreon qui a le Plugin `centreon-plugin-Cloud-Prometheus-Api`:

```bash
/usr/lib/centreon/plugins//centreon_prometheus_api.pl \
--plugin=cloud::prometheus::restapi::plugin \
--mode=target-status \
--hostname=<Prometheus FQDN> \
--url-path='/api/v1' \
--port='443' \
--proto='https' \
--insecure  \
--header="Authorization: Bearer <Token API>" \
--verbose \
--warning-status=''  \
--critical-status='%{health} !~ /up/'
```

Exemple de resultat:
```
Target 'https://172.25.152.253:10250/metrics' health is 'up' [endpoint = https-metrics][job = kubelet][metrics_path = /metrics][instance = 172.25.152.253:10250][namespace = kube-system][node = master-1.sand-4b7b.asten.maq][service = kubelet]
...
```

Exemple de filtre:

```bash
/usr/lib/centreon/plugins//centreon_prometheus_api.pl \
--plugin=cloud::prometheus::restapi::plugin \
--mode=target-status \
--hostname=<Prometheus FQDN> \
--url-path='/api/v1' \
--port='443' \
--proto='https' \
--insecure  \
--header="Authorization: Bearer <Token API>" \
--verbose \
--warning-status=''  \
--critical-status='%{health} !~ /up/' \
--filter-label="namespace,kube-system"
```

Pour ajouter le service sur l'hôte:
```bash
centreon -u admin -p Pa55w.rd -o Service -a ADD -v "<Nom de l'hôte>;target-status;Cloud-Prometheus-Target-Status-Api-custom"
```

**Expressions**

Pour surveiller une metrique en particulier, il faudra connaitre ses attributs:

```
aggregator_openapi_v2_regeneration_count{apiservice="*",reason="startup"} 0
...
```

Dans l'exemple ci-dessus, la metrique a pour nom `aggregator_openapi_v2_regeneration_count` et pour attribut `apiservice`, `reason`, la metrique comporte la valeur `0` et ses attributs comportent les valeurs `"*"` et `"startup"` respectivement.

Pour tester si Centreon n'a pas d'erreur lors de son execution de la commande:

```bash
/usr/lib/centreon/plugins//centreon_prometheus_api.pl \
--plugin=cloud::prometheus::restapi::plugin \
--mode=expression \
--hostname=<FQDN Prometheus> \
--url-path='/api/v1' \
--port='443' \
--proto='https' \
[--insecure] \
--header="Authorization: Bearer <TOKEN API OPENSHIFT>" \
--verbose \
--query='<centreon label>,<PromQL Requete>' \
--output="<Sortie explicatif de la requete>" \
--instance="<attribut>" \
--warning-status='' \
--critical-status='<Regle d'erreur>' \
--use-new-perfdata
```

Exemple de commande de test pour la metrique `aggregator_openapi_v2_regeneration_count`:

```bash
/usr/lib/centreon/plugins//centreon_prometheus_api.pl \
--plugin=cloud::prometheus::restapi::plugin \
--mode=expression \
--hostname=prometheus-k8s-openshift-monitoring.apps.exemple.com \
--url-path='/api/v1' \
--port='443' \
--proto='https' \
[--insecure] \
--header="Authorization: Bearer someAPItoken" \
--verbose \
--query='aggregatorvalue,aggregator_openapi_v2_regeneration_count == 0' \
--output="Aggregator has value of %{aggregatorvalue} for reason %{instance}" \
--instance="reason" \
--warning-status='' \
--critical-status='%{aggregatorvalue} == 1' \
--use-new-perfdata
```

Pour ajouter le service sur l'hôte:
```bash
centreon -u admin -p Pa55w.rd -o Service -a ADD -v "<Nom de l'hôte>;<Description du service>;Cloud-Prometheus-Expression-Api-custom;"
```

Une fois les commandes appliqué, exporter la configuration et recharger le Centreon Central. [Documentation ici](#Recharger-Centreon)

Annexes
=======

PromQL
------

La documentation sur les requêtes PromQL peut etre retrouvé sur le lien suivant: <br/>
https://prometheus.io/docs/prometheus/latest/querying/basics/

Centreon CLI
------------

La documentation et l'utilisation de la ligne de commande de centreon peut être retrouvé sur lien suivant: <br />
https://docs.centreon.com/current/en/api/clapi.html

Recharger Centreon
------------------

Pour deployer une configuration, les étapes peuvent être retrouvées sur cette [documentation](https://docs.centreon.com/current/en/monitoring/monitoring-servers/deploying-a-configuration.html)