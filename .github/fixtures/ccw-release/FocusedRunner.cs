using System;

public static class FocusedRunner
{
    public static int Main(string[] args)
    {
        int result = args.Length > 0 && args[0] == "leak"
            ? Tests.CallableWrapperLeakTest()
            : Tests.CallableWrapperOverReleaseTest();
        Console.WriteLine("result=" + result);
        if (result == 0)
            Console.WriteLine("CCW_TEST_PASS");
        return result;
    }
}

