# Set up Sample CoreDNS CNF
./sample-cnfs/sample-coredns-cnf/readme.md
# Prerequistes
### Install helm
```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```
### Optional: Use a helm version manager
https://github.com/yuya-takeyama/helmenv
Check out helmenv into any path (here is ${HOME}/.helmenv)
```
${HOME}/.helmenv)
$ git clone https://github.com/yuya-takeyama/helmenv.git ~/.helmenv
```
Add ~/.helmenv/bin to your $PATH any way you like
```
$ echo 'export PATH="$HOME/.helmenv/bin:$PATH"' >> ~/.bash_profile
```
```
helmenv versions 
helmenv install <version 3.1?>
```

### core-dns installation
```
helm install coredns stable/coredns
```
### Pull down the helm chart code, untar it, and put it in the cnfs/coredns directory
```
helm pull stable/coredns
```
### Example cnti-testsuite config file for sample-core-dns-cnf
In ./cnfs/sample-core-dns-cnf/cnti-testsuite.yaml
```
---
container_names: [coredns-coredns] 
```
