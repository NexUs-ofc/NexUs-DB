# Containers e Kubernetes

Este repositório contém dados e rotinas batch, não uma API. O container executa a RPA existente (`python -m rpa.src.main`); o Kubernetes usa um Job manual, sem Service ou porta HTTP.

Padrão: Dockerfile na raiz, usuário sem root, credenciais externas, Kustomize no namespace `nexus`, imagem `nexus-db:local` substituível por qualquer registry. A CI apenas compila a imagem e renderiza os manifests, sem publicar ou executar migrações.

## Imagem local

```sh
docker build -t nexus-db:local .
docker run --rm --env-file .env nexus-db:local
```

Esse comando **executa a migração**. Configure primeiro os bancos de origem e destino e siga `rpa/README.md`. A imagem não sobe PostgreSQL/MongoDB nem aplica automaticamente as migrations Flyway.

## Configuração e credenciais

Prepare um arquivo `.env` local a partir das variáveis documentadas no README e em `.env.example` (quando existir). Ele nunca deve entrar na imagem nem no Git. Bancos e serviços externos precisam ser alcançáveis a partir do cluster; `localhost` dentro do Pod é o próprio container.

```sh
kubectl apply -f k8s/namespace.yaml
kubectl create secret generic nexus-db-secret --namespace nexus --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -
```

O Secret é fornecido externamente, sem valores fictícios versionados. Atualizações exigem reiniciar o workload para recarregar variáveis de ambiente.

## Kubernetes em qualquer cluster

É necessário um cluster configurado no seu kubeconfig. Para usar registry remoto:

1. Compile e publique a imagem em um registry sob seu controle.
2. Dentro de `k8s/`, execute `kubectl kustomize` após ajustar `images` no `kustomization.yaml` (ou use `kustomize edit set image nexus-db=REGISTRY/PROJETO/nexus-db:TAG`). `REGISTRY`, `PROJETO` e `TAG` são substituições obrigatórias para esse exemplo.
3. Em registry privado, configure `imagePullSecrets` no cluster. Não é necessário um registry específico.

Para Kind/Minikube, carregue `nexus-db:local` nos nós usando `kind load docker-image` ou `minikube image load`. A política `IfNotPresent` permite a imagem local.

```sh
kubectl kustomize k8s
kubectl apply -k k8s
kubectl wait --for=condition=complete job/nexus-db -n nexus --timeout=30m
kubectl logs -n nexus job/nexus-db
```

O Job tem `parallelism: 1`, `completions: 1` e `backoffLimit: 0` para evitar repetição automática da migração. Para executar novamente, remova apenas o Job concluído e reaplique; não execute instâncias concorrentes nem junto com a RPA agendada do GitHub Actions. Os logs ficam no stdout; o arquivo local do Pod é temporário.

## Referências

- https://docs.docker.com/build/building/multi-stage/
- https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
