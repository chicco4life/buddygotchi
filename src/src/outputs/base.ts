/**
 * Output layer base types.
 */

import type { Engine } from "../core/engine.js";

export interface OutputProvider {
  readonly outputId: string;

  /** Start the provider. Subscribe to engine state changes. */
  start(engine: Engine): Promise<void>;

  /** Stop the provider. Clean up connections. */
  stop(): Promise<void>;
}
