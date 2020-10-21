SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Jean Paul
-- Create date: 21/10/2020
-- Description:	Retorna a situação do funcionário baseada no dado histórico.
-- =============================================
CREATE FUNCTION [dbo].[retornarSituacaoFuncionario] 
(
	-- Add the parameters for the function here
	@funcicodigo int, @data datetime
)
RETURNS char(1)
AS
BEGIN
	-- Declare the return variable here
	DECLARE @funcscodigo char(1)

	-- Add the T-SQL statements to compute the return value here
	select top 1 @funcscodigo = coalesce(funcscodigo ,0)
	from tbgabcentrocustofuncionario (nolock) 
	where funcicodigo = @funcicodigo and convert(date,cenfudatainicio) <= @data
	order by centfudatacadastro desc

	-- Return the result of the function
	RETURN @funcscodigo

END
GO
