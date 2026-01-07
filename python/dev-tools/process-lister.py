# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "psutil",
# ]
# ///

import psutil
import argparse
import time
from typing import List, Tuple

class ProcessLister:
    """Class to list running processes sorted by memory usage (like Activity Monitor)."""

    def __init__(self, limit: int = 10):
        self.limit = limit

    def get_processes(self) -> List[Tuple[int, str, float, float]]:
        """Retrieve processes with RSS memory (macOS Activity Monitor's 'Real Memory')."""
        processes = []
        
        # Use RSS (Resident Set Size) for macOS compatibility
        for proc in psutil.process_iter(['pid', 'name', 'memory_info']):
            try:
                mem_info = proc.info['memory_info']
                if mem_info:  # Ensure memory info is available
                    rss_mb = mem_info.rss / (1024 * 1024)  # Convert bytes to MB
                    # Initialize CPU measurement
                    proc.cpu_percent(interval=None)
                    processes.append((proc, proc.info['pid'], proc.info['name'], rss_mb))
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue

        # Allow time for CPU% calculation
        time.sleep(0.2)
        
        # Collect CPU usage and finalize data
        results = []
        for proc, pid, name, rss_mb in processes:
            try:
                cpu = proc.cpu_percent(interval=None)
                results.append((pid, name, rss_mb, cpu))
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue

        # Sort by RSS memory (descending)
        results.sort(key=lambda x: x[2], reverse=True)
        return results[:self.limit]

    def display_processes(self):
        """Print processes in a table format."""
        processes = self.get_processes()
        print(f"{'PID':<8} {'Memory (MB)':<12} {'CPU %':<6} Process Name")
        for pid, name, mem, cpu in processes:
            print(f"{pid:<8} {mem:<12.2f} {cpu:<6.1f} {name}")

def main():
    parser = argparse.ArgumentParser(description="List processes sorted by memory usage (macOS-friendly).")
    parser.add_argument("--limit", type=int, default=10, help="Number of processes to display.")
    args = parser.parse_args()
    
    ProcessLister(args.limit).display_processes()

if __name__ == "__main__":
    main()