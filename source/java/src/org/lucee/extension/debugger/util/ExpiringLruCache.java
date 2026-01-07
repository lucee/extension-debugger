package org.lucee.extension.debugger.util;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantLock;

/**
 * A simple LRU cache with time-based expiration.
 * Thread-safe via explicit locking.
 *
 * Replaces Guava's CacheBuilder.newBuilder().maximumSize().expireAfterWrite().build()
 */
public class ExpiringLruCache<K, V> {

	private final int maxSize;
	private final long expireAfterWriteMillis;
	private final ReentrantLock lock = new ReentrantLock();

	private final LinkedHashMap<K, Entry<V>> map;

	private static class Entry<V> {
		final V value;
		final long writeTime;

		Entry(V value) {
			this.value = value;
			this.writeTime = System.currentTimeMillis();
		}

		boolean isExpired(long expireAfterMillis) {
			return System.currentTimeMillis() - writeTime > expireAfterMillis;
		}
	}

	/**
	 * Creates a new ExpiringLruCache.
	 *
	 * @param maxSize maximum number of entries
	 * @param expireAfterWrite time after which entries expire
	 * @param unit time unit for expireAfterWrite
	 */
	public ExpiringLruCache(int maxSize, long expireAfterWrite, TimeUnit unit) {
		this.maxSize = maxSize;
		this.expireAfterWriteMillis = unit.toMillis(expireAfterWrite);
		// accessOrder=true means iteration order is from least-recently-accessed to most-recently-accessed
		// Note: We inline the eldest entry removal logic in put() to avoid anonymous inner class issues
		// with the agent's class injection mechanism
		this.map = new LinkedHashMap<K, Entry<V>>(16, 0.75f, true);
	}

	/**
	 * Gets a value from the cache.
	 *
	 * @param key the key to look up
	 * @return the value, or null if not present or expired
	 */
	public V get(K key) {
		lock.lock();
		try {
			Entry<V> entry = map.get(key);
			if (entry == null) {
				return null;
			}
			if (entry.isExpired(expireAfterWriteMillis)) {
				map.remove(key);
				return null;
			}
			return entry.value;
		}
		finally {
			lock.unlock();
		}
	}

	/**
	 * Puts a value into the cache.
	 *
	 * @param key the key
	 * @param value the value
	 */
	public void put(K key, V value) {
		lock.lock();
		try {
			map.put(key, new Entry<>(value));
			// Evict eldest entries if over capacity
			while (map.size() > maxSize) {
				K eldest = map.keySet().iterator().next();
				map.remove(eldest);
			}
		}
		finally {
			lock.unlock();
		}
	}

	/**
	 * Removes a value from the cache.
	 *
	 * @param key the key to remove
	 */
	public void invalidate(K key) {
		lock.lock();
		try {
			map.remove(key);
		}
		finally {
			lock.unlock();
		}
	}

	/**
	 * Clears all entries from the cache.
	 */
	public void invalidateAll() {
		lock.lock();
		try {
			map.clear();
		}
		finally {
			lock.unlock();
		}
	}

	/**
	 * Returns the current size of the cache.
	 * Note: may include expired entries that haven't been cleaned up yet.
	 */
	public int size() {
		lock.lock();
		try {
			return map.size();
		}
		finally {
			lock.unlock();
		}
	}
}
