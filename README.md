# 🚀 Cronicle-Edge: Distributed Task Scheduler

Bem-vindo ao instalador automatizado do **Cronicle-Edge** para Proxmox VE. 

Este repositório fornece uma maneira rápida e interativa de provisionar um servidor Master do Cronicle-Edge em uma Máquina Virtual dedicada (Debian 13) no seu cluster Proxmox, pronto para uso em ambiente de produção.

---

## 🌐 O que é o Cronicle-Edge?

O **Cronicle-Edge** é um moderno e poderoso agendador e executor de tarefas distribuídas (Task Scheduler/Runner). Ele é um *fork* atualizado do projeto original Cronicle, projetado para gerenciar e executar rotinas em múltiplos servidores a partir de um único painel centralizado.

Desenvolvido em Node.js, ele substitui as antigas e difíceis *cronjobs* de sistema operacional por uma interface web elegante, onde você pode agendar, monitorar e auditar todas as tarefas da sua infraestrutura em tempo real.

### ✨ Principais Benefícios e Funções

* **Painel Web Centralizado:** Esqueça o terminal. Crie, edite e monitore rotinas através de uma interface gráfica web rica e intuitiva.
* **Arquitetura Distribuída (Master / Worker):** Você pode ter um servidor central (Master) coordenando o trabalho e dezenas de servidores satélites (Workers) executando as tarefas na ponta.
* **Execução em Múltiplas Linguagens:** Suporte nativo para executar scripts em Shell/Bash, Node.js, Python, PHP, Perl, entre outros.
* **Logs em Tempo Real:** Acompanhe o output (`stdout` e `stderr`) de cada tarefa enquanto ela acontece, direto pelo navegador.
* **Tratamento de Erros e Alertas:** Configure notificações automáticas (E-mail, Slack, Webhooks) caso uma tarefa falhe ou demore mais do que o esperado.
* **Controle de Concorrência e Retentativas:** Defina limites de execução simultânea para não sobrecarregar servidores e configure *auto-retries* para tarefas que falham por instabilidades de rede.
* **Alta Disponibilidade (HA):** Suporte a failover automático. Se um servidor Worker cair, o Master pode redirecionar a tarefa para outro servidor disponível na mesma categoria.

---

## 🖥️ Requisitos Mínimos da VM (Configurados no Script)

Para garantir que o Cronicle-Edge Master rode com fluidez e tenha espaço para armazenar logs e histórico de tarefas, a Máquina Virtual gerada utilizará as seguintes especificações:

* **Sistema Operacional:** Debian 13 (Trixie) - *Cloud Image*
* **CPU:** 2 Cores
* **Memória RAM:** 2 GB
* **Armazenamento:** 20 GB (Disco VirtIO SCSI)

---

## ⚡ Instalação Rápida (Proxmox Shell)

Para instalar o Cronicle-Edge Master, acesse o **Shell** do seu nó Proxmox e execute o comando abaixo em uma única linha:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/joaodanielcs/Cronicle/refs/heads/main/vm_install.sh)"
```

## 🔑 Acesso Pós-Instalação

Assim que o instalador concluir:

1. Acesse a **Base URL** ou o **IP** que você configurou no seu navegador (ex: `http://cronicle.seudominio.com.br`).
2. Na tela inicial, faça o login utilizando a credencial padrão do sistema:

> 👤 **Usuário:** `admin`  
> 🔑 **Senha:** `admin`

⚠️ **Aviso Importante:** Por questões de segurança, lembre-se de alterar a senha do administrador e configurar o seu servidor DNS local imediatamente após o primeiro acesso.
