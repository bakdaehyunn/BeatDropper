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
});
