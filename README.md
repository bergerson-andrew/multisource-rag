# multi-source-rag

A retrieval-augmented generation system that answers questions over content pulled from multiple data sources, stored in both SQL and Blob. Documents are ingested, indexed, and made searchable, then combined with an LLM to produce grounded answers with source context.

## Azure architecture

| Service | Resource | Purpose |
|---|---|---|
| Resource Group | `azurerm_resource_group` | Container for all resources belonging to this project, so they can be managed and torn down together. |
| Blob Storage | `azurerm_storage_account` + `azurerm_storage_container` | Landing zone for raw source documents before they're chunked/embedded, and the durable store those documents are re-fetched from. |
| Azure AI Search (Basic) | `azurerm_search_service` | Vector/keyword index that RAG queries run against — stores document chunks and their embeddings and handles retrieval at query time. |
| Azure SQL (Basic) | `azurerm_mssql_server` + `azurerm_mssql_database` | Relational store for application metadata: source registry, ingestion status, document-to-chunk mappings, and similar structured state that doesn't belong in the search index. |
| Azure OpenAI — chat deployment | `azurerm_cognitive_deployment` (`chat`) | Generates the final answer from a user's question plus the chunks retrieved from AI Search. |
| Azure OpenAI — embedding deployment | `azurerm_cognitive_deployment` (`embedding`) | Converts document chunks and incoming queries into vectors for similarity search in AI Search. |

