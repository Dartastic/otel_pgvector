// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_pgvector_suppression.dart';

const _tracerName = 'dartastic_otel_libs_pgvector';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedPgvectorSearch` callback.
class PgvectorSearchResult<T> {
  const PgvectorSearchResult({required this.value, this.resultCount});
  final T value;
  final int? resultCount;
}

/// Wraps a pgvector similarity query (SELECT ... ORDER BY embedding
/// <-> $1 LIMIT N) in a CLIENT span. db.system=postgresql plus
/// vector_db.* fields recognized by Dartastic dashboards.
Future<T> tracedPgvectorSearch<T>({
  required String table,
  required Future<PgvectorSearchResult<T>> Function() invoke,
  String? indexType,
  String? distanceOperator,
  int? topK,
  int? embeddingDim,
  String? database,
}) async {
  if (pgvectorInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': 'postgresql',
    'db.operation': 'vector_search',
    'db.collection.name': table,
    'pgvector.table': table,
  };
  if (database != null) m['db.name'] = database;
  if (indexType != null) m['pgvector.index.type'] = indexType;
  if (distanceOperator != null) {
    m['pgvector.distance.operator'] = distanceOperator;
  }
  if (topK != null) m['vector_db.search.top_k'] = topK;
  if (embeddingDim != null) m['vector_db.embedding.dim'] = embeddingDim;

  final span = _tracer().startSpan(
    'pgvector search $table',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.resultCount != null) {
      span.addAttributes(OTel.attributes([
        OTel.attributeInt('vector_db.search.result_count', r.resultCount!),
      ]));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
