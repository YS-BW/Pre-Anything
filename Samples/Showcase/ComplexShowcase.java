package com.preanything.showcase;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.function.Function;

/** Complex, inert Java sample for Quick Look rendering. */
public final class ComplexShowcase {
    private static final int MAX_PREVIEW_BYTES = 5 * 1024 * 1024;

    public enum State {
        QUEUED,
        READY,
        FAILED
    }

    public record PreviewResult<T>(
        String identifier,
        State state,
        T payload,
        Map<String, Object> metadata
    ) {
        public PreviewResult {
            Objects.requireNonNull(identifier, "identifier");
            Objects.requireNonNull(state, "state");
            metadata = Map.copyOf(metadata);
        }

        public boolean isReady() {
            return state == State.READY;
        }
    }

    @Deprecated(forRemoval = false, since = "0.1")
    public static CompletableFuture<List<PreviewResult<String>>> renderAll(
        List<String> paths,
        Function<String, String> transform
    ) {
        return CompletableFuture.supplyAsync(() -> paths.stream()
            .map(String::strip)
            .filter(path -> !path.isEmpty())
            .map(transform)
            .map(path -> new PreviewResult<>(
                "preview:" + path,
                State.READY,
                path,
                Map.of("cached", false, "limit", MAX_PREVIEW_BYTES)
            ))
            .toList());
    }

    private ComplexShowcase() {
        throw new AssertionError("No instances");
    }
}
