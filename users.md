# Table des matières

1. [Gestion des utilisateurs](#Gestion-des-utilisateurs)
   1. [kubeadmin](#kubeadmin)
   2. [HTPasswd](#HTPasswd)
   3. [LDAP](#LDAP)
   4. [LDAPSync](#LDAPSync)
   5. [Droit Openshift](#Droit-Openshift)

# Gestion des utilisateurs

## kubeadmin

L'utilisateur kubeadmin est un utilisateur créer au moment de la création du cluster Openshift, il est recommandé de supprimer ce compte à la fin de la configuration quand au moins 1 utilisateur a été attribué avec le rôle `cluster-admin`.

Pour supprimer l'utilisateur kubeadmin, il suffit de supprimer le secret `kubeadmin` contenu dans le projet `kube-system`. 

Attention: Si aucun utilisateur est attribué avec le rôle `cluster-admin`, il faudra réinstaller le cluster entièrement. 

## HTPasswd

Il est possible de rajouté des utilisateurs par le biais de l'utilitaire `htpasswd` si aucune source d'identité existe.

La commande suivante va permettre la création d'un utilisateur avec l'outil `htpasswd`:

```shell
htpasswd -c -B -b <nom du fichier htpasswd> <utilisateur> <mot de passe> ## non interactive
htpasswd -c -B <nom du fichier htpasswd> <utilisateur> ## interactive
```

Pour continuer d'ajouté des utilisateurs sur un fichier `htpasswd` existant:

```shell
htpasswd -B -b <nom du fichier htpasswd> <utilisateur> <mot de passe> ## non interactive
htpasswd -B <nom du fichier htpasswd> <utilisateur> ## interactive
```

Pour supprimer des utilisateurs sur un fichier htpasswd existant:

```shell
htpasswd -D <nom du fichier htpasswd> <utilisateur>
```

Une fois les utilisateurs créés, le fichier doit être placé dans un secret avec la clef `htpasswd` sous le projet `openshift-config`

```shell
oc create secret generic <nom du secret> --from-file=htpasswd=<nom du fichier htpasswd> -n openshift-config
```

Il faudra modifier l'operateur OAuth pour que celle-ci utilise le secret via `oc edit oauth` et ajouté une entrée sur le chemin `spec.identityProvider`.

Voici un exemple d'entrée:

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider 
    mappingMethod: claim 
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd_users ## <nom du secret>
```

Noté que `identityProviders` prend une liste en paramètre, il est donc possible d'avoir plusieurs sources d'identités.

## LDAP

Pour utiliser un annuaire LDAP en tant que source d'identité, il faudra ajouté une entrée sur le chemin `spec.identity.provider` et donner un compte de service à l'opérateur `OAuth` pour l'authentification auprès de l'annuaire.

Voice un exemple d'entrée pour un annuaire LDAP Active Directory:

```yaml
  identityProviders:
  - ldap:
      attributes:
        email:
        - userPrincipalName
        id:
        - dn
        name:
        - name
        preferredUsername:
        - userPrincipalName
      bindDN: CN=ocp_oauth_svc,CN=Users,DC=example,DC=com
      bindPassword:
        name: ldap-secret
      insecure: true
      url: ldap://example.com/cn=Users,dc=example,dc=com?sAMAccountName?sub?(objectClass=person)
    mappingMethod: claim
    name: ldapidp
    type: LDAP
```

## LDAPSync

Il est possible de synchroniser des groupes d'un annuaire LDAP vers Openshift en utilisant la ressource YAML LDAPSync.

Exemple de ressource LDAPSync:

```yaml
kind: LDAPSyncConfig
apiVersion: v1
url: ldap://example.com:389
bindDN: cn=openshift_svc,cn=users,dc=example,dc=com
bindPassword:
  file: /etc/secret/bind_password
insecure: true
activeDirectory:
    usersQuery:
        baseDN: "cn=users,dc=example,dc=com"
        scope: sub
        derefAliases: never
        filter: (objectclass=person)
        pageSize: 0
    userNameAttributes: [ userPrincipalName ]
    groupMembershipAttributes: [ memberOf ]
```

Après avoir créé le fichier yaml, il faut utiliser la commande `oc adm groupes --sync-config=<nom du fichier yaml>.yaml --confirm` pour synchroniser les groupes.

NOTE: Pour automatiser la synchronisation, il est possible d'utiliser un `cronjob`.

## Droit Openshift

Par défaut, il existe des rôles déjà existant pour administrer le cluster, ces rôles peuvent être attribuer à l'aide des commandes suivantes: 

 - `oc adm policy add-cluster-role-to-user <role> <utilisateur>`  pour un utilisateur.
 - `oc adm policy add-cluster-role-to-group <role> <groupe>` pour un groupe.
 - `oc adm policy add-cluster-role-to-user <role> -z <serviceaccount> -n <namespace>` pour un `serviceaccount`

Il est aussi possible d'attribuer ces rôles seulement sur un projet avec la commande `oc adm policy add-role-to-* -n <projet> <role><utilisateur>`, cela permet a l'utilisateur de n'avoir que des droits sur le projet.

Voici une liste des rôles existant (non exhaustive) sur Openshift

| Rôle               | Description                                                  |
| ------------------ | ------------------------------------------------------------ |
| `cluster-admin`    | Un super-utilisateur qui peut effectuer n'importe quelle action dans n'importe quel projet. Lorsqu'il est lié à un utilisateur sur un projet, il a le contrôle total des quotas et de toutes les actions sur toutes les ressources du projet. |
| `cluster-status`   | Permet de voir le statut du cluster                          |
| `basic-user`       | Un utilisateur qui peut obtenir des informations de base sur les projets et les utilisateurs. |
| `admin`            | Un project manager, s'il est utilisé dans une liaison locale, un administrateur a le droit de visualiser toute ressource dans le projet et de modifier toute ressource dans le projet, à l'exception des quotas. |
| `view`             | Un utilisateur qui ne peut effectuer aucune modification, mais qui peut voir la plupart des objets d'un projet. Il ne peut pas voir ou modifier les rôles ou les liens. |
| `edit`             | Un utilisateur qui peut modifier la plupart des objets d'un projet mais qui n'a pas le pouvoir de visualiser ou de modifier les rôles ou les liens. |
| `self-provisioner` | Un utilisateur qui peut créer ses propres projets.           |

Pour pouvoir enlever des utilisateurs d'un `clusterrole`, il est possibles d'utiliser les commandes suivantes:

- `oc adm policy remove-cluster-role-from-user <role> <utilisateur>` pour un utilisateur.
- `oc adm policy remove-cluster-role-from-group <role> <groupe>` pour un groupe.
- `oc adm policy remove-cluster-role-from-user <role> -z <serviceaccount> -n <namespace>` pour un `serviceaccount`.

La manipulation est similaire pour lié un utilisateur seulement au niveau projet, il suffira d'enlever le mot `cluster` de toutes les commandes comme ceci:

- `oc adm policy add-role-to-user <role> <utilisateur> -n <namespace>`
- `oc adm policy add-role-to-group <role> <groupe> -n <namespace>`
- `oc adm policy remove-role-from-user <role> <utilisateur> -n <namespace>`
- `oc adm policy remove-role-from-group <role> <groupe> -n <namespace>`

