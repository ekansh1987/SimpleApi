using System;
using Xunit;
using SimpleApi;
using SimpleApi.Controllers;

namespace SimpleApi.Tests
{
    public class UnitTest1
    {
        ValuesController objValue=new ValuesController();
        [Fact]
        public void Test1()
        {
           var temp=objValue.Get(1);
           Assert.Equal("ekansh",temp);
        }
    }
}
