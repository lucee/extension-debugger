package org.lucee.extension.debugger.util;

import java.lang.ref.ReferenceQueue;
import java.lang.ref.WeakReference;
import java.util.AbstractMap;
import java.util.Collection;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/**
 * A concurrent map with weak keys. When a key becomes weakly reachable and is
 * garbage collected, its entry is automatically removed from the map.
 *
 * Replaces Guava's MapMaker().weakKeys().makeMap()
 */
public class ConcurrentWeakKeyMap<K, V> implements ConcurrentMap<K, V> {

	private final ConcurrentHashMap<IdentityWeakReference<K>, V> map = new ConcurrentHashMap<>();
	private final ReferenceQueue<K> queue = new ReferenceQueue<>();

	/**
	 * Creates a new ConcurrentWeakKeyMap with default concurrency level.
	 */
	public ConcurrentWeakKeyMap() {
	}

	/**
	 * Creates a new ConcurrentWeakKeyMap.
	 * @param concurrencyLevel ignored, kept for API compatibility
	 */
	public ConcurrentWeakKeyMap(int concurrencyLevel) {
		// concurrencyLevel is ignored - ConcurrentHashMap handles this internally
	}

	private void expungeStaleEntries() {
		IdentityWeakReference<?> ref;
		while ((ref = (IdentityWeakReference<?>) queue.poll()) != null) {
			map.remove(ref);
		}
	}

	@Override
	public V get(Object key) {
		expungeStaleEntries();
		return map.get(new LookupKey<>(key));
	}

	@Override
	public V put(K key, V value) {
		expungeStaleEntries();
		return map.put(new IdentityWeakReference<>(key, queue), value);
	}

	@Override
	public V putIfAbsent(K key, V value) {
		expungeStaleEntries();
		return map.putIfAbsent(new IdentityWeakReference<>(key, queue), value);
	}

	@Override
	public V remove(Object key) {
		expungeStaleEntries();
		return map.remove(new LookupKey<>(key));
	}

	@Override
	public boolean remove(Object key, Object value) {
		expungeStaleEntries();
		return map.remove(new LookupKey<>(key), value);
	}

	@Override
	public V replace(K key, V value) {
		expungeStaleEntries();
		return map.replace(new IdentityWeakReference<>(key, queue), value);
	}

	@Override
	public boolean replace(K key, V oldValue, V newValue) {
		expungeStaleEntries();
		return map.replace(new IdentityWeakReference<>(key, queue), oldValue, newValue);
	}

	@Override
	public boolean containsKey(Object key) {
		expungeStaleEntries();
		return map.containsKey(new LookupKey<>(key));
	}

	@Override
	public boolean containsValue(Object value) {
		expungeStaleEntries();
		return map.containsValue(value);
	}

	@Override
	public int size() {
		expungeStaleEntries();
		return map.size();
	}

	@Override
	public boolean isEmpty() {
		expungeStaleEntries();
		return map.isEmpty();
	}

	@Override
	public void clear() {
		map.clear();
		while (queue.poll() != null); // drain queue
	}

	@Override
	public void putAll(Map<? extends K, ? extends V> m) {
		expungeStaleEntries();
		for (Entry<? extends K, ? extends V> e : m.entrySet()) {
			put(e.getKey(), e.getValue());
		}
	}

	@Override
	public Set<K> keySet() {
		expungeStaleEntries();
		Set<K> keys = new HashSet<>();
		for (IdentityWeakReference<K> ref : map.keySet()) {
			K key = ref.get();
			if (key != null) {
				keys.add(key);
			}
		}
		return keys;
	}

	@Override
	public Collection<V> values() {
		expungeStaleEntries();
		return map.values();
	}

	@Override
	public Set<Entry<K, V>> entrySet() {
		expungeStaleEntries();
		Set<Entry<K, V>> entries = new HashSet<>();
		for (Entry<IdentityWeakReference<K>, V> e : map.entrySet()) {
			K key = e.getKey().get();
			if (key != null) {
				entries.add(new AbstractMap.SimpleEntry<>(key, e.getValue()));
			}
		}
		return entries;
	}

	/**
	 * WeakReference that uses identity-based equality (System.identityHashCode).
	 */
	private static class IdentityWeakReference<T> extends WeakReference<T> {
		private final int hashCode;

		IdentityWeakReference(T referent, ReferenceQueue<? super T> queue) {
			super(referent, queue);
			this.hashCode = System.identityHashCode(referent);
		}

		@Override
		public int hashCode() {
			return hashCode;
		}

		@Override
		public boolean equals(Object obj) {
			if (this == obj) return true;
			if (obj instanceof IdentityWeakReference) {
				Object myReferent = get();
				Object otherReferent = ((IdentityWeakReference<?>) obj).get();
				return myReferent != null && myReferent == otherReferent;
			}
			if (obj instanceof LookupKey) {
				Object myReferent = get();
				Object otherReferent = ((LookupKey<?>) obj).referent;
				return myReferent != null && myReferent == otherReferent;
			}
			return false;
		}
	}

	/**
	 * Key wrapper for lookups that doesn't require creating a WeakReference.
	 * Uses identity-based equality to match IdentityWeakReference.
	 */
	private static class LookupKey<T> {
		final T referent;
		final int hashCode;

		LookupKey(Object referent) {
			@SuppressWarnings("unchecked")
			T t = (T) referent;
			this.referent = t;
			this.hashCode = System.identityHashCode(referent);
		}

		@Override
		public int hashCode() {
			return hashCode;
		}

		@Override
		public boolean equals(Object obj) {
			if (obj instanceof IdentityWeakReference) {
				Object otherReferent = ((IdentityWeakReference<?>) obj).get();
				return referent != null && referent == otherReferent;
			}
			if (obj instanceof LookupKey) {
				return referent != null && referent == ((LookupKey<?>) obj).referent;
			}
			return false;
		}
	}
}
