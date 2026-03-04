import multiprocessing
import os

# Global variable at the module level
# In the parent it will be "ABC123XYZ" after main() starts.
# In the children, we will use an initializer to push it into this global slot.
access_token = None

def init_worker(token):
    """ 
    This is the BTS-A 'Injection' pattern.
    It runs ONCE when the child process starts, setting the global variable
    before any actual tasks are executed.
    """
    global access_token
    access_token = token

def worker_task(task_id):
    """
    This function doesn't receive the token as an argument.
    It relies purely on the global variable 'access_token'.
    """
    pid = os.getpid()
    print(f"Child Process PID: {pid} (Task {task_id}) using Global Token: {access_token}")

def main():
    # Parent acquires the token
    shared_token = "ABC123XYZ-INTERCEPTED"
    print(f"Parent Process PID: {os.getpid()} - Intercepted Token: {shared_token}")

    # Using a Pool with an initializer is the most robust way to 'share' a global
    # on Windows/MacOS (spawn/forkserver).
    with multiprocessing.Pool(processes=5, initializer=init_worker, initargs=(shared_token,)) as pool:
        pool.map(worker_task, range(5))

    print("\nAll workers completed.")

if __name__ == "__main__":
    main()
