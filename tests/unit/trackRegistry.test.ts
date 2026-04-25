import { TrackRegistry } from '../../src/main/trackRegistry';

describe('TrackRegistry', () => {
  it('resolves registered track paths by id', () => {
    const registry = new TrackRegistry();
    registry.replace([
      { trackId: 'track-1', filePath: '/tmp/one.mp3' },
      { trackId: 'track-2', filePath: '/tmp/two.mp3' }
    ]);

    expect(registry.resolvePath('track-1')).toBe('/tmp/one.mp3');
    expect(registry.resolvePath('track-2')).toBe('/tmp/two.mp3');
    expect(registry.size).toBe(2);
  });

  it('rejects invalid track identifiers', () => {
    const registry = new TrackRegistry();
    registry.replace([{ trackId: 'track-1', filePath: '/tmp/one.mp3' }]);

    expect(() => registry.resolvePath('')).toThrow('Invalid track id');
    expect(() => registry.resolvePath(123)).toThrow('Invalid track id');
  });

  it('rejects unresolved ids and replaces old entries', () => {
    const registry = new TrackRegistry();
    registry.replace([{ trackId: 'track-1', filePath: '/tmp/one.mp3' }]);
    registry.replace([{ trackId: 'track-2', filePath: '/tmp/two.mp3' }]);

    expect(() => registry.resolvePath('track-1')).toThrow('Track is not authorized');
    expect(registry.resolvePath('track-2')).toBe('/tmp/two.mp3');
  });

  it('keeps existing entries when appending new tracks', () => {
    const registry = new TrackRegistry();
    registry.replace([{ trackId: 'track-1', filePath: '/tmp/one.mp3' }]);
    registry.append([{ trackId: 'track-2', filePath: '/tmp/two.mp3' }]);

    expect(registry.resolvePath('track-1')).toBe('/tmp/one.mp3');
    expect(registry.resolvePath('track-2')).toBe('/tmp/two.mp3');
    expect(registry.size).toBe(2);
  });

  it('expires stale entries based on authorization ttl', () => {
    let now = 1_700_000_000_000;
    const registry = new TrackRegistry(() => now);
    registry.replace([{ trackId: 'track-1', filePath: '/tmp/one.mp3' }]);

    now += 24 * 60 * 60 * 1000 + 1;
    expect(() => registry.resolvePath('track-1')).toThrow('Track is not authorized');
  });

  it('prunes oldest entries when registry grows beyond cap', () => {
    let now = 1_700_000_000_000;
    const registry = new TrackRegistry(() => now);

    const firstBatch = Array.from({ length: 1_100 }, (_, index) => ({
      trackId: `old-${index}`,
      filePath: `/tmp/old-${index}.mp3`
    }));
    registry.append(firstBatch);

    now += 1;
    expect(registry.resolvePath('old-0')).toBe('/tmp/old-0.mp3');
    now += 1;

    const secondBatch = Array.from({ length: 901 }, (_, index) => ({
      trackId: `new-${index}`,
      filePath: `/tmp/new-${index}.mp3`
    }));
    registry.append(secondBatch);

    expect(registry.size).toBe(2_000);
    expect(registry.resolvePath('old-0')).toBe('/tmp/old-0.mp3');
    expect(() => registry.resolvePath('old-1')).toThrow('Track is not authorized');
  });
});
