#include "treereduce.h"
#include "utils.h"

using namespace clang;

static std::string formatTreereduceOp(int op)
{
    switch (op)
    {
        case 0: return "add";
        case 1: return "max";
        case 2: return "min";
    }

    assert(false);
    return "";
}

static OperationMetadata extractTreereduce(CallExpr* channelDecl)
{
    return OperationMetadata("treereduce",
                             extractIntArg(channelDecl, 3),
                             extractDataType(channelDecl, 1),
                             extractBufferSize(channelDecl, 6),
                             { {"op_type", formatTreereduceOp(extractIntArg(channelDecl, 2))} }
    );
}

OperationMetadata TreereduceExtractor::GetOperationMetadata(CallExpr* callExpr)
{
    return extractTreereduce(extractChannelDecl(callExpr));
}
std::string TreereduceExtractor::CreateDeclaration(const std::string& callName, const OperationMetadata& metadata)
{
    return "void " + this->RenameCall(callName, metadata) + "(SMI_TreereduceChannel* chan,  void* data_snd, void* data_rcv);";
}
std::vector<std::string> TreereduceExtractor::GetFunctionNames()
{
    return {"SMI_Treereduce"};
}

OperationMetadata TreereduceChannelExtractor::GetOperationMetadata(CallExpr* callExpr)
{
    return extractTreereduce(callExpr);
}
std::string TreereduceChannelExtractor::CreateDeclaration(const std::string& callName, const OperationMetadata& metadata)
{
    return this->CreateChannelDeclaration(callName, metadata, "SMI_TreereduceChannel", "int count, SMI_Datatype data_type, SMI_Op op, int port, int root, SMI_Comm comm");
}
std::string TreereduceChannelExtractor::GetChannelFunctionName()
{
    return "SMI_Open_treereduce_channel";
}
