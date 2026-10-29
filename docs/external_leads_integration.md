# API de Integração de Leads Externos

Endpoint de integração para sincronização de leads, dados de atribuição de anúncios, negociações no pipeline e agendamentos a partir de CRMs externos (ex.: Bitrix24, n8n, etc.).

---

## 1. Rota e Autenticação

* **Método:** `POST`
* **URL:** `/public/api/v1/integrations/external_leads`
* **Headers:**
  * `Content-Type: application/json`
  * `X-API-Key: <token>` (ou `api_access_token: <token>`)

---

## 2. Payload da Requisição

```json
{
  "source": "bitrix24",
  "external_id": "272315",
  "contact": {
    "name": "Cássia Rodrigues",
    "phone_number": "+5561985702132",
    "email": "cassia@example.com",
    "created_at": "2026-10-29T16:38:20+03:00"
  },
  "referral": {
    "source_id": "120260810960180456",
    "source_type": "ad",
    "source_url": "https://www.instagram.com/p/DfAsPvEAo-_/",
    "headline": "Chamar no WhatsApp",
    "ctwa_clid": "AfheykVY92LBMq9RRg8O0aBhuf6Q..."
  },
  "deal": {
    "title": "Cássia Rodrigues - Whatsapp - Tráfego",
    "pipeline_id": "ab180f48-f637-425e-bcd2-41fe45fdc57a",
    "stage_id": "837dd70f-999a-466c-9b90-6fdf5133d819",
    "value": 1800.00
  },
  "appointments": [
    {
      "external_id": "deal_272315_eval",
      "start_time": "2026-11-03T06:00:00+03:00",
      "end_time": "2026-11-03T07:00:00+03:00",
      "duration_minutes": 60,
      "status": "scheduled",
      "price": 0.0,
      "title": "Avaliação - Cássia Rodrigues",
      "category": "Geral",
      "professional_email": "atendimento@lumombeauty.com.br"
    }
  ]
}
```

### Detalhes dos Campos

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `source` | String | Sim | Identificador da fonte externa (ex: `bitrix24`). |
| `external_id` | String | Sim | ID único da negociação no sistema de origem. |
| `contact.name` | String | Sim | Nome completo do lead. |
| `contact.phone_number` | String | Sim | Telefone no formato E.164 (`+<DDI><DDD><Número>`). |
| `contact.email` | String | Não | E-mail opcional (não gera conflito se já existir). |
| `contact.created_at` | ISO 8601 | Não | Data real de criação no sistema de origem (só retrocede). Não pode ser data futura. |
| `referral.source_id` | String | Não | ID do anúncio Meta Ads (`ad_id`). |
| `referral.source_type` | String | Não | Tipo de origem (`ad` ou `post`). |
| `referral.source_url` | String | Não | Link da campanha/anúncio. |
| `referral.headline` | String | Não | Título do anúncio. |
| `referral.ctwa_clid` | String | Não | Identificador de clique Click-to-WhatsApp. |
| `deal.pipeline_id` | UUID | Sim | ID do funil no Evolution CRM. |
| `deal.stage_id` | UUID | Sim | ID da etapa correspondente no funil. |
| `deal.value` | Decimal | Não | Valor estimado ou fechado da negociação. |
| `appointments[].external_id` | String | Sim | ID estável do agendamento (ex: `deal_<ID>_eval`). |
| `appointments[].start_time` | ISO 8601 | Sim | Data e hora de início do agendamento. |
| `appointments[].status` | String | Sim | `scheduled`, `confirmed`, `attended`, `no_show`, `cancelled`, `rescheduled`. |
| `appointments[].price` | Decimal | Não | Valor cobrado/receita (usado quando `status = attended`). |
| `appointments[].professional_email` | String | Não | E-mail do profissional (fallback para default se não encontrado). |

---

## 3. Respostas

### Sucesso (201 Created - Primeiro envio)
```json
{
  "success": true,
  "contact": {
    "id": "e4b9c1d0-...",
    "action": "created"
  },
  "pipeline_item": {
    "id": "a1f8e2c3-...",
    "action": "created"
  },
  "appointments": [
    {
      "id": "d7b2a9e1-...",
      "external_id": "deal_272315_eval",
      "action": "created"
    }
  ]
}
```

### Sucesso (200 OK - Reenvio sem alterações)
```json
{
  "success": true,
  "contact": {
    "id": "e4b9c1d0-...",
    "action": "unchanged"
  },
  "pipeline_item": {
    "id": "a1f8e2c3-...",
    "action": "unchanged"
  },
  "appointments": [
    {
      "id": "d7b2a9e1-...",
      "external_id": "deal_272315_eval",
      "action": "unchanged"
    }
  ]
}
```

### Erro de Autenticação (401 Unauthorized)
```json
{
  "success": false,
  "error": "API key is missing"
}
```

### Erro de Validação (422 Unprocessable Content)
```json
{
  "success": false,
  "error": "contact.phone_number must be in E.164 format",
  "errors": [
    "contact.phone_number must be in E.164 format"
  ]
}
```
