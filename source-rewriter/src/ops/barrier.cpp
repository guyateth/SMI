#include "barrier.h"
#include "utils.h"

using namespace clang;

static OperationMetadata extractBarrier(CallExpr* channelDecl)
{
    return OperationMetadata("barrier",
                             extractIntArg(channelDecl, 1),
                             DataType::Int,
                             extractBufferSize(channelDecl, 3)
    );
}

OperationMetadata BarrierExtractor::GetOperationMetadata(CallExpr* callExpr)
{
    return extractBarrier(extractChannelDecl(callExpr));
}
std::string BarrierExtractor::CreateDeclaration(const std::string& callName, const OperationMetadata& metadata)
{
    return "void " + this->RenameCall(callName, metadata) + "(SMI_BarrierChannel* chan);";
}
std::vector<std::string> BarrierExtractor::GetFunctionNames()
{
    return {"SMI_Barrier"};
}

OperationMetadata BarrierChannelExtractor::GetOperationMetadata(CallExpr* callExpr)
{
    return extractBarrier(callExpr);
}
std::string BarrierChannelExtractor::CreateDeclaration(const std::string& callName, const OperationMetadata& metadata)
{
    return this->CreateChannelDeclaration(callName, metadata, "SMI_BarrierChannel", "int count, int port, SMI_Comm comm");
}
std::string BarrierChannelExtractor::GetChannelFunctionName()
{
    return "SMI_Open_barrier_channel";
}
