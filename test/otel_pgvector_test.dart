// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_pgvector/otel_pgvector.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_pgvector-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('search records CLIENT span', () async {
    await tracedPgvectorSearch<String>(
      table: 'embeddings',
      indexType: 'hnsw',
      distanceOperator: '<=>',
      topK: 10,
      embeddingDim: 1536,
      database: 'app',
      invoke: () async => const PgvectorSearchResult(
        value: 'rows',
        resultCount: 10,
      ),
    );
    final a = attrsOf(spans.findSpanByName('pgvector search embeddings')!);
    expect(a['db.system'], 'postgresql');
    expect(a['db.operation'], 'vector_search');
    expect(a['db.collection.name'], 'embeddings');
    expect(a['pgvector.table'], 'embeddings');
    expect(a['pgvector.index.type'], 'hnsw');
    expect(a['pgvector.distance.operator'], '<=>');
    expect(a['vector_db.search.top_k'], 10);
    expect(a['vector_db.embedding.dim'], 1536);
    expect(a['vector_db.search.result_count'], 10);
    expect(a['db.name'], 'app');
  });

  test('suppression skips spans', () async {
    await runWithoutPgvectorInstrumentationAsync(() async {
      await tracedPgvectorSearch<String>(
        table: 'e',
        invoke: () async => const PgvectorSearchResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('pgvector '), isEmpty);
  });
}
