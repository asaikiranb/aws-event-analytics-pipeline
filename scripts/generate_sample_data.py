#!/usr/bin/env python3
"""
Generate sample event data for capstone project exploration.

Creates representative files matching Lambda output format:
- Gzipped JSON Lines
- Same schema as production Lambda
- Smaller volume for local testing (1000 events per file)
- Output to local directory
"""

import json
import gzip
import argparse
from pathlib import Path
from datetime import datetime, timezone, timedelta
import sys

# Add lambda directory to path to import event generator
sys.path.insert(0, str(Path(__file__).parent / 'lambda'))
from event_generator import generate_events


def generate_sample_files(output_dir: Path, num_files: int = 6, events_per_file: int = 1000):
    """
    Generate sample event files.

    Args:
        output_dir: Directory to write sample files
        num_files: Number of files to generate (default 6 = 1 hour at 10-min intervals)
        events_per_file: Events per file (default 1000 for quick testing)
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Generating {num_files} sample files with {events_per_file:,} events each")
    print(f"Output directory: {output_dir}")

    # Generate files with realistic timestamps (10-minute intervals)
    base_time = datetime.now(timezone.utc) - timedelta(hours=1)

    for i in range(num_files):
        # Calculate timestamp for this file
        file_time = base_time + timedelta(minutes=10 * i)
        timestamp_str = file_time.strftime("%Y%m%d-%H%M%S")

        # Generate events
        events = generate_events(events_per_file)

        # Update timestamps to match file time
        for event in events:
            event["timestamp"] = file_time.isoformat()

        # Convert to JSON Lines (with trailing newline for proper line counting)
        jsonl_content = '\n'.join(json.dumps(event) for event in events) + '\n'

        # Compress
        compressed_content = gzip.compress(jsonl_content.encode('utf-8'))

        # Write file with realistic path structure
        file_path = output_dir / f"events-{timestamp_str}.jsonl.gz"
        file_path.write_bytes(compressed_content)

        print(f"  Created: {file_path.name} ({len(compressed_content):,} bytes, {events_per_file:,} events)")

    print(f"\nSample data generation complete!")
    print(f"Total events: {num_files * events_per_file:,}")
    print(f"\nTo explore the data:")
    print(f"  1. Decompress: gunzip {output_dir}/events-*.jsonl.gz")
    print(f"  2. View: head {output_dir}/events-*.jsonl")
    print(f"  3. Count: wc -l {output_dir}/events-*.jsonl")


def main():
    parser = argparse.ArgumentParser(description="Generate sample event data for capstone project")
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=Path('classes/wk10-capstone/sample-data'),
        help='Output directory for sample files (default: classes/wk10-capstone/sample-data)'
    )
    parser.add_argument(
        '--num-files',
        type=int,
        default=6,
        help='Number of files to generate (default: 6 for 1 hour)'
    )
    parser.add_argument(
        '--events-per-file',
        type=int,
        default=1000,
        help='Events per file (default: 1000 for testing, production is 500k-750k)'
    )

    args = parser.parse_args()

    generate_sample_files(
        output_dir=args.output_dir,
        num_files=args.num_files,
        events_per_file=args.events_per_file
    )


if __name__ == '__main__':
    main()
