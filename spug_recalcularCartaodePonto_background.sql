SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Jean Paul
-- Create date: 19/07/2019
-- Description:	Recalcula o cartão de ponto fazendo as críticas.
-- =============================================
-- ATUALIZAÇÕES
-- =============================================
-- Author:		Jean Paul
-- alter date: 30/07/2019
-- 1º Trocado a SP incluiOcorrencias de lugar, para dentro do cursor de dias pois quando funcionário em mais de um acordo coletivo, chama a SP mais de uma vez.
-- 2º alter date: 08/08/2019 Implementado os campos relacionados a lei do motorista
-- alter date: 23/08/2019
-- 1º Implementado a SP que atualiza o saldo e o saldo anterior do funcionário no CP
-- =============================================
ALTER PROCEDURE [dbo].[spug_recalcularCartaodePonto_background] 
	-- Add the parameters for the function here
	@funcicodigo int,@mes smallint, @ano int, @usuarcodigo int, @itprocodigo int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	-- VARIÁVEIS
	DECLARE
	@periodoiniciodatabase datetime, 
	@periodofimdatabase datetime, 
	@escala_vinculada bit = 0,
	@mov_or_cc_bloq bit,
	@func_ativo bit = 0,
	@sit_f char(2),
	@cartacodigo int,
	@cartasaldobh int,
	@cartacreditobh int,
	@cartadebitobh int,
	@cartasaldoanterior int,
	-- VARIÁVEIS USADAS NO CURSOR DE DADOS HISTÓRICOS
	@dia smallint,
	@dt date,
	@codigo_h int,
	@horarcodigo int, -- valor recuperado da tabela cartão de ponto
	@indicacao char(20),
	@cod_escala int,
	@ctococodigo int,
	@centccodigo int,
	@feriado bit,
	@feriatipo char(1),
	@acordcodigo int,
	@cargocodigo int,
	@tpapocodigo int,
	@flagocorrencia bit,
	@count int,
	@nacional bit,
	@municipal bit,
	@regional bit,
	@jornadalivre bit,
	@inicionoturno datetime,
	@fimnoturno datetime,
	@fatornoturno float,
	@estendenoturno bit,
	@cartaadn int,
	@cartacargahoraria int,
	@carta_previsto_e1 datetime,
	@carta_previsto_s1 datetime,
	@carta_previsto_e2 datetime,
	@carta_previsto_s2 datetime,
	@carta_previsto_e3 datetime,
	@carta_previsto_s3 datetime,
	@carta_previsto_e4 datetime,
	@carta_previsto_s4 datetime,
	@carta_realizado_e1 datetime, 
	@carta_realizado_s1 datetime,
	@carta_realizado_e2 datetime, 
	@carta_realizado_s2 datetime,
	@carta_realizado_e3 datetime, 
	@carta_realizado_s3 datetime,
	@carta_realizado_e4 datetime, 
	@carta_realizado_s4 datetime,
	@carta_justificativa_e1 int,
	@carta_justificativa_s1 int,
	@carta_justificativa_e2 int,
	@carta_justificativa_s2 int,
	@carta_justificativa_e3 int,
	@carta_justificativa_s3 int,
	@carta_justificativa_e4 int,
	@carta_justificativa_s4 int,
	@carta_tolerancia_anterior_e1 int, 
	@carta_tolerancia_posterior_e1 int, 
	@carta_tolerancia_anterior_s1 int, 
	@carta_tolerancia_posterior_s1 int,
	@carta_tolerancia_anterior_e2 int, 
	@carta_tolerancia_posterior_e2 int, 
	@carta_tolerancia_anterior_s2 int, 
	@carta_tolerancia_posterior_s2 int,
	@carta_tolerancia_anterior_e3 int, 
	@carta_tolerancia_posterior_e3 int, 
	@carta_tolerancia_anterior_s3 int, 
	@carta_tolerancia_posterior_s3 int,
	@carta_tolerancia_anterior_e4 int, 
	@carta_tolerancia_posterior_e4 int, 
	@carta_tolerancia_anterior_s4 int, 
	@carta_tolerancia_posterior_s4 int,
	@cartacargahorariarealizada int, 
	@cartahorasfalta int, 
	@horapontodecorte int,
	@minutopontodecorte int,
	@datapontodecorte datetime ,
	@pis char(11),
	@aptr datetime,
	@num int,
	@ult_apt_anterior datetime = NULL,
	@contadorafd int,
	@contadorcartaodeponto int,
	@ult_apt datetime = NULL,
	@dt_auxiliar datetime = NULL,
	@horaespera int = NULL,
	@horaparada int = NULL,
	@horadirecao int = NULL,
	@horaintervcpl int = NULL,
	@horaintervsdesc int = NULL,
	@horainterjornadacompl int = NULL,
	@horainterjornadacomplsdesc int = NULL,
	@leimotorista bit, -- INFORMA SE FUNCIONÁRIO É OU NÃO LEI DO MOTORISTA
	-- INFORMA SE FUNCIONÁRIO É OU NÃO BANCO DE HORAS BASEADO NO DADO HISTÓRICO. ALTERAÇÃO FEITA EM 01/06/2020 POR JEAN PAUL.
	@bancodehoras bit /*= dbo.retornarSituacaoBhFuncionario(@funcicodigo,EOMONTH(convert(varchar(4),@ano)+'-'+convert(varchar,@mes)+'-01'))*/,
	@compljornada int, -- INFORMA SE EVENTO COMPLEMENTA OU NÃO A JORNADA DO DIA
	@contjornada int,
	@dataadmissao datetime,
	@afdtgcodigo int, @afdtgcodigo_e1 int,@afdtgcodigo_s1 int,@afdtgcodigo_e2 int,@afdtgcodigo_s2 int,@afdtgcodigo_e3 int,@afdtgcodigo_s3 int,@afdtgcodigo_e4 int,@afdtgcodigo_s4 int,
	@cartadesconsiderapreassinalado bit, @cartahorarreferencia smallint, @datademissao datetime
	
	select @pis = funcipis, @datademissao = funcidatademissao, @dataadmissao = funcidataadmissao from tbgabfuncionario (nolock) where funcicodigo = @funcicodigo
	
	-- DECLARAÇÃO DA TABELA DE CARTÃO DE PONTO
	DECLARE @cartaodeponto table (sem_mov_or_cc_bloq bit,escala_vinculada bit,func_ativo bit,periodoinicio datetime, periodofim datetime)

	-- PERÍODO INÍCIO E FIM DE MOVIMENTAÇÃO
	select @periodoiniciodatabase = min(perioiniciodatabase),@periodofimdatabase = max(periofimdatabase) from tbgabperiodomovimentacao (nolock) 
	where centccodigo in (select centccodigo from tbgabcentrocustofuncionario (nolock) where funcicodigo = @funcicodigo) 
	and dbo.verificaCentrocustoBloqueado(perioiniciodatabase,centccodigo) = 0 
	and periomesbase = @mes 
	and perioanobase = @ano 
	and (centccodigo in (
	select centccodigo from tbgabresponsavelcentrocustoassoc RC (nolock)
	inner join tbgabresponsavelcentrocusto R on RC.respccodigo=R.respccodigo
	where R.usuarcodigo = @usuarcodigo) or 
	((select usuargestorsistema from tbgabusuario (nolock) where usuarcodigo = @usuarcodigo) = 1)) 

	-- SITUAÇÃO 1 -> CARTÃO DE PONTO SEM PERÍODO DE MOVIMENTAÇÃO PARA A DATA INFORMADA OU CENTRO DE CUSTO BLOQUEADO
	if @periodoiniciodatabase is null or @periodofimdatabase is null
	begin
		set @mov_or_cc_bloq = 1
		insert into @cartaodeponto values (@mov_or_cc_bloq,NULL,NULL,NULL,NULL)
	end

	-- SITUAÇÃO 0 -> CARTÃO DE PONTO COM PERÍODO DE MOVIMENTAÇÃO PARA A DATA INFORMADA E CENTRO DE CUSTO NÃO SE ENCONTRA BLOQUEADO
	else
	begin
		set @mov_or_cc_bloq = 0
		set @escala_vinculada = (select case when count(fuesccodigo) > 0 then 1 else 0 end from tbgabfuncionarioescala (nolock) 
								 where funcicodigo = @funcicodigo and fuescdatainiciovigencia <= @periodoiniciodatabase)

		-- SE NÃO POSSUI ESCALA VINCULADA PARA O PERÍODO INFORMADO
		if @escala_vinculada = 0
		begin
			insert into @cartaodeponto values (@mov_or_cc_bloq,@escala_vinculada,NULL,@periodoiniciodatabase,@periodofimdatabase)
		end

		-- SE POSSUI ESCALA VINCULADA PARA O PERÍODO INFORMADO
		else
		begin
			if (coalesce(@datademissao,'1900-01-01 00:00:00.000') = '1900-01-01 00:00:00.000')
			begin
				set @datademissao = @periodofimdatabase
			end

			-- ALTERAÇÃO 15/06/2020. ID DA DEMANDA: 36
			/* CÓDIGO IMPLEMENTADO */
			-- INÍCIO
			select @leimotorista = dbo.retornarSituacaoLeiMotoristaFuncionario(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase)
			select @bancodehoras = dbo.retornarSituacaoBhFuncionario(@funcicodigo,@periodofimdatabase)
			-- FIM
			-- DELETA OS CARTÕES TOTALIZADORES DE OCORRÊNCIAS
			delete from tbgabcartaototalizador where funcicodigo = @funcicodigo and cartomesbase = @mes and cartoanobase = @ano and catcartocodigo in (9,10,14,15,17,114,115)
			set @func_ativo = 1
			declare @ctococodigo2 int = 0
			-- RETORNAR DADOS HISTÓRICOS DO FUNCIONÁRIO	
			declare dados_historicos cursor for
			select	
			dia,
			dt,
			coalesce(codigo_h,0),	
			indicacao,
			cod_escala,
			coalesce(CO.ctococodigo,0),
			coalesce(centccodigo,0),
			feriado,
			feriatipo,
			coalesce(acordcodigo,0),
			coalesce(cargocodigo,0),
			coalesce(tpapocodigo,0),
			flagocorrencia
			from dbo.retornarDadosHistoricosFuncionario(@funcicodigo,@periodoiniciodatabase,@periodofimdatabase)
			left join tbgabcartaoocorrencia CO (nolock) on dbo.retornarDadosHistoricosFuncionario.indicacao=CO.ctocodescricao
			where dt <= @datademissao and dt >= @dataadmissao
			open dados_historicos
			fetch next from dados_historicos 
			into @dia,@dt,@codigo_h,@indicacao,@cod_escala,@ctococodigo,@centccodigo,@feriado,@feriatipo,@acordcodigo,@cargocodigo,@tpapocodigo,@flagocorrencia
			while @@FETCH_STATUS=0
			begin
				set @cartacodigo = null
				select top 1 @cartacodigo=cartacodigo from tbgabcartaodeponto (nolock) where cartadatajornada = @dt and funcicodigo = @funcicodigo
				set @cartacargahorariarealizada = NULL
				set @cartacargahoraria = NULL
				set @ctococodigo2 = @ctococodigo
				set @cartacargahorariarealizada = NULL
				set @cartacargahoraria = NULL
				set @carta_realizado_e1 = NULL
				set @carta_realizado_s1 = NULL
				set @carta_realizado_e2 = NULL
				set @carta_realizado_s2 = NULL
				set @carta_realizado_e3 = NULL
				set @carta_realizado_s3 = NULL
				set @carta_realizado_e4 = NULL
				set @carta_realizado_s4 = NULL
				set @carta_previsto_e1 = NULL
				set @carta_previsto_s1 = NULL
				set @carta_previsto_e2 = NULL
				set @carta_previsto_s2 = NULL
				set @carta_previsto_e3 = NULL
				set @carta_previsto_s3 = NULL
				set @carta_previsto_e4 = NULL
				set @carta_previsto_s4 = NULL
				set @carta_tolerancia_anterior_e1=NULL
				set @carta_tolerancia_anterior_s1=NULL
				set @carta_tolerancia_posterior_e1=NULL
				set @carta_tolerancia_posterior_s1=NULL
				set @carta_tolerancia_anterior_e2=NULL
				set @carta_tolerancia_anterior_s2=NULL
				set @carta_tolerancia_posterior_e2=NULL
				set @carta_tolerancia_posterior_s2=NULL
				set @carta_tolerancia_anterior_e3=NULL
				set @carta_tolerancia_anterior_s3=NULL
				set @carta_tolerancia_posterior_e3=NULL
				set @carta_tolerancia_posterior_s3=NULL
				set @carta_tolerancia_anterior_e4=NULL
				set @carta_tolerancia_anterior_s4=NULL
				set @carta_tolerancia_posterior_e4=NULL
				set @carta_tolerancia_posterior_s4=NULL
				-- VERIFICA SE JÁ EXISTE UM REGISTRO PARA O DIA CORRENTE
				if @cartacodigo is not null
				begin
					-- CHAVE PRIMÁRIA DA TABELA CARTÃO DE PONTO
					select top 1 @cartadesconsiderapreassinalado=cartadesconsiderapreassinalado,@cartahorarreferencia=cartahorarreferencia from tbgabcartaodeponto (nolock) where cartacodigo = @cartacodigo
					set @horarcodigo = @codigo_h

					-- SE NÃO HÁ ACORDO COLETIVO PARA O DIA
					if @acordcodigo = 0
					begin
						-- SE A INDICAÇÃO PARA O DIA FOR <> DE TRABALHO
						if @indicacao <> 'Trabalho'
						begin
							set @jornadalivre = 1
						end
						-- SE A INDICAÇÃO PARA O DIA FOR = TRABALHO
						else
						begin
							set @jornadalivre = null
						end
						set @inicionoturno = null
						set @fimnoturno = null
						set @fatornoturno = null
						set @estendenoturno = null
						set @cartaadn = 0
					end

					-- SE HÁ ACORDO COLETIVO PARA O DIA
					else
					begin
						-- SE A INDICAÇÃO FOR FOLGA OU DSR.
						if @ctococodigo = 2 or @ctococodigo = 3 
						begin 
							set @jornadalivre = 1
						end
						else
						begin
							set @jornadalivre = (select acordjornadalivre from tbgabacordocoletivo (nolock) where acordcodigo = @acordcodigo)
						end
						select 
						@inicionoturno=inicionoturno,
						@fimnoturno=fimnoturno,
						@fatornoturno=fatornoturno,
						@estendenoturno=estendenoturno from dbo.retornarInicioFimNoturno(@acordcodigo,@dt)
						set @cartaadn = 0
					end
					
					set @nacional = 0
					set @regional = 0
					set @municipal = 0
	
					-- VERIFICA SE O DIA É FERIADO E QUAL O TIPO DE FERIADO
					if @feriado = 1
					begin
						if @feriatipo = 'N' begin set @nacional = 1 end
						if @feriatipo = 'M' begin set @municipal = 1 end
						if @feriatipo = 'R' begin set @regional = 1 end
					end
	
					-- SE HÁ HORÁRIO PARA O DIA
					if @horarcodigo <> 0
					begin
						select 
						@cartacargahoraria=horarcargahoraria,
						@carta_tolerancia_anterior_e1=horartoleranciaanteriorentrada1,
						@carta_tolerancia_anterior_s1=horartoleranciaanteriorsaida1,
						@carta_tolerancia_posterior_e1=horartoleranciaposteriorentrada1,
						@carta_tolerancia_posterior_s1=horartoleranciaposteriorsaida1,
						@carta_tolerancia_anterior_e2=horartoleranciaanteriorentrada2,
						@carta_tolerancia_anterior_s2=horartoleranciaanteriorsaida2,
						@carta_tolerancia_posterior_e2=horartoleranciaposteriorentrada2,
						@carta_tolerancia_posterior_s2=horartoleranciaposteriorsaida2,
						@carta_tolerancia_anterior_e3=horartoleranciaanteriorentrada3,
						@carta_tolerancia_anterior_s3=horartoleranciaanteriorsaida3,
						@carta_tolerancia_posterior_e3=horartoleranciaposteriorentrada3,
						@carta_tolerancia_posterior_s3=horartoleranciaposteriorsaida3,
						@carta_tolerancia_anterior_e4=horartoleranciaanteriorentrada4,
						@carta_tolerancia_anterior_s4=horartoleranciaanteriorsaida4,
						@carta_tolerancia_posterior_e4=horartoleranciaposteriorentrada4,
						@carta_tolerancia_posterior_s4=horartoleranciaposteriorsaida4
						from tbgabhorario (nolock) where horarcodigo = @horarcodigo

						select 
						@carta_previsto_e1=e1,@carta_previsto_s1=s1,
						@carta_previsto_e2=e2,@carta_previsto_s2=s2,
						@carta_previsto_e3=e3,@carta_previsto_s3=s3,
						@carta_previsto_e4=e4,@carta_previsto_s4=s4 
						from dbo.retornarHorariosPrevistos(@horarcodigo,@dt)
					end

					-- ALTERADO DIA 10/06/2020. SE HÁ CONFLITO DE ESCALAS, MUDA A REFERÊNCIA DE HORÁRIO
					if dbo.retornarConflitoEscala(@dt,@funcicodigo,@carta_previsto_e1) = 1 begin set @cartahorarreferencia = 2 end else begin set @cartahorarreferencia = 1 end

					-- CURSOR PARA RODAR OS APTS REALIZADOS
					DECLARE realizadas CURSOR FOR
					-- ALTERAÇÃO 15/06/2020. ID DA DEMANDA: 36
					select horarios,num,afdtgcodigo from dbo.retornarApontamentosRealizadosComPreAssinalados2(@funcicodigo,@dt,@codigo_h,@jornadalivre,@ctococodigo,0,@cartahorarreferencia,/* CÓDIGO ALTERADO */@leimotorista/* CÓDIGO ALTERADO */)
					OPEN realizadas
					FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
					WHILE @@FETCH_STATUS = 0
					BEGIN
							if @num = 1 begin set @carta_realizado_e1 = @aptr set @afdtgcodigo_e1 = @afdtgcodigo end
					else if @num = 2 begin set @carta_realizado_s1 = @aptr set @afdtgcodigo_s1 = @afdtgcodigo end
					else if @num = 3 begin set @carta_realizado_e2 = @aptr set @afdtgcodigo_e2 = @afdtgcodigo end
					else if @num = 4 begin set @carta_realizado_s2 = @aptr set @afdtgcodigo_s2 = @afdtgcodigo end
					else if @num = 5 begin set @carta_realizado_e3 = @aptr set @afdtgcodigo_e3 = @afdtgcodigo end
					else if @num = 6 begin set @carta_realizado_s3 = @aptr set @afdtgcodigo_s3 = @afdtgcodigo end
					else if @num = 7 begin set @carta_realizado_e4 = @aptr set @afdtgcodigo_e4 = @afdtgcodigo end
					else if @num = 8 begin set @carta_realizado_s4 = @aptr set @afdtgcodigo_s4 = @afdtgcodigo end
					FETCH NEXT FROM realizadas INTO @aptr,@num,@afdtgcodigo
					END
					CLOSE realizadas
					DEALLOCATE realizadas

					-- TESTA SE O FUNCIONÁRIO É LEI DO MOTORISTA
					if @leimotorista = 1 begin 
						set @horaespera = (select sum(horasespera) from dbo.retornarTempoEsperaLeidoMotorista(@pis,@dt))
						set @horaparada = (select sum(horasparada) from dbo.retornarTempoParadaLeidoMotorista(@pis,@dt))
						set @horadirecao = (select sum(horasdirecao) from dbo.retornarTempoDirecaoLeidoMotorista(@pis,@dt))
						set @horaintervcpl = (select sum(horasintervcpl) from dbo.retornarTempoIntervCplLeidoMotorista(@pis,@dt))
						set @horaintervsdesc = (select sum(horasintervsemdesc) from dbo.retornarTempoIntervSemDescLeidoMotorista(@pis,@dt))
						set @horainterjornadacompl = (select sum(horasinterjornadacompl) from dbo.retornarTempoInterjornadaComplLeidoMotorista(@pis,@dt))
						set @horainterjornadacomplsdesc = (select SUM(horasinterjornadasdesc) from dbo.retornarTempoInterjornadaSemDescLeidoMotorista(@pis,@dt))
					end
					
					if (select top 1 ctococodigo from tbgabcartaodeponto (nolock) where cartacodigo = @cartacodigo) = 0 and @cod_escala is not null and @cod_escala <> 0
					begin
						update tbgabcartaodeponto set ctococodigooriginal = @ctococodigo2,ctococodigo = @ctococodigo2 where cartacodigo = @cartacodigo
					end

					-- ATUALIZA VALORES
					update tbgabcartaodeponto set
					cargocodigo = @cargocodigo,
					funcicodigo = @funcicodigo,
					acordcodigo = @acordcodigo,
					horarcodigo = @horarcodigo,
					ctococodigo = @ctococodigo,
					cartacargahoraria = @cartacargahoraria,
					carta_previsto_e1 = @carta_previsto_e1,
					carta_previsto_s1 = @carta_previsto_s1,
					carta_previsto_e2 = @carta_previsto_e2,
					carta_previsto_s2 = @carta_previsto_s2,
					carta_previsto_e3 = @carta_previsto_e3,
					carta_previsto_s3 = @carta_previsto_s3,
					carta_previsto_e4 = @carta_previsto_e4,
					carta_previsto_s4 = @carta_previsto_s4,
					cartaferiadonacional = @nacional,										
					cartaferiadoregional = @regional,
					cartaferiadomunicipal = @municipal,
					centccodigo = @centccodigo,
					cartamesbase = @mes,
					cartaanobase = @ano,
					carta_realizado_e1 = @carta_realizado_e1,
					carta_realizado_s1 = @carta_realizado_s1,
					carta_realizado_e2 = @carta_realizado_e2,
					carta_realizado_s2 = @carta_realizado_s2,
					carta_realizado_e3 = @carta_realizado_e3,
					carta_realizado_s3 = @carta_realizado_s3,
					carta_realizado_e4 = @carta_realizado_e4,
					carta_realizado_s4 = @carta_realizado_s4,
					afdtgcodigo_e1 = @afdtgcodigo_e1,
					afdtgcodigo_s1 = @afdtgcodigo_s1,
					afdtgcodigo_e2 = @afdtgcodigo_e2,
					afdtgcodigo_s2 = @afdtgcodigo_s2,
					afdtgcodigo_e3 = @afdtgcodigo_e3,
					afdtgcodigo_s3 = @afdtgcodigo_s3,
					afdtgcodigo_e4 = @afdtgcodigo_e4,
					afdtgcodigo_s4 = @afdtgcodigo_s4,
					cartainicionoturno = @inicionoturno,
					cartafimnoturno = @fimnoturno,
					cartafatornoturno = @fatornoturno,
					cartaestendenoturno = @estendenoturno,
					cartajornadalivre = @jornadalivre,
					cartaadn = @cartaadn,
					carta_tolerancia_anterior_e1 = @carta_tolerancia_anterior_e1,
					carta_tolerancia_posterior_e1 = @carta_tolerancia_posterior_e1,
					carta_tolerancia_anterior_s1 = @carta_tolerancia_anterior_s1,
					carta_tolerancia_posterior_s1 = @carta_tolerancia_posterior_s1,
					carta_tolerancia_anterior_e2 = @carta_tolerancia_anterior_e2,
					carta_tolerancia_posterior_e2 = @carta_tolerancia_posterior_e2,
					carta_tolerancia_anterior_s2 = @carta_tolerancia_anterior_s2,
					carta_tolerancia_posterior_s2 = @carta_tolerancia_posterior_s2,
					carta_tolerancia_anterior_e3 = @carta_tolerancia_anterior_e3,
					carta_tolerancia_posterior_e3 = @carta_tolerancia_posterior_e3,
					carta_tolerancia_anterior_s3 = @carta_tolerancia_anterior_s3,
					carta_tolerancia_posterior_s3 = @carta_tolerancia_posterior_s3,
					carta_tolerancia_anterior_e4 = @carta_tolerancia_anterior_e4,
					carta_tolerancia_posterior_e4 = @carta_tolerancia_posterior_e4,
					carta_tolerancia_anterior_s4 = @carta_tolerancia_anterior_s4,
					carta_tolerancia_posterior_s4 = @carta_tolerancia_posterior_s4,
					cartaflagferiado = @feriado,
					cartaflagocorrencia = @flagocorrencia,
					cartasaldoanteriorbh = @cartasaldoanterior,
					cartacreditobh = @cartacreditobh,
					cartadebitobh = @cartadebitobh,
					cartasaldoatualbh = @cartasaldobh,
					cartaespera = @horaespera,
					cartaparada = @horaparada,
					cartadirecao = @horadirecao,
					cartaintervcpl = @horaintervcpl,
					cartaintervsdesc = @horaintervsdesc,
					cartainterjornadacompl = @horainterjornadacompl,
					cartainterjornadacomplsdesc = @horainterjornadacomplsdesc,
					cartahorasextra = null,
					cartaprocessadopor = @usuarcodigo,
					cartadataultimoprocessaamento = getdate(),
					-- ALTERADO AQUI, 10/06/2020.
					cartahorarreferencia = @cartahorarreferencia
					where cartacodigo = @cartacodigo

					-- PEGA HORA REALIZADA
					set @cartacargahorariarealizada = (select minuto from dbo.retornarSomaHorasFuncionario(@cartacodigo))
					
					-- ATUALIZA HORA REALIZADA
					update tbgabcartaodeponto set cartacargahorariarealizada = @cartacargahorariarealizada where cartacodigo = @cartacodigo
					
					-- INCLUI TOTALIZADORES
					exec dbo.spug_incluirTotalizadores @acordcodigo, @funcicodigo, @dt, 'spug_recalcularCartaodePonto_background'

					-- ATUALIZA HORAS FALTA
					set @cartahorasfalta = (select horasfalta from dbo.retornarSomaHorasFuncionario(@cartacodigo))
					update tbgabcartaodeponto set cartahorasfalta = @cartahorasfalta where cartacodigo = @cartacodigo

				end
				
				insert into @cartaodeponto values (
				@mov_or_cc_bloq, -- 1
				@escala_vinculada, -- 2
				@func_ativo, -- 3
				@periodoiniciodatabase, -- 4
				@periodofimdatabase) -- 5
				
			fetch next from dados_historicos 
			into @dia,@dt,@codigo_h,@indicacao,@cod_escala,@ctococodigo,@centccodigo,@feriado,@feriatipo,@acordcodigo,@cargocodigo,@tpapocodigo,@flagocorrencia
			end -- END CURSOR dados_historicos
			close dados_historicos
			deallocate dados_historicos
			-- INCLUI OCORRÊNCIAS
			exec dbo.spug_incluirOcorrencias @mes,@ano, @funcicodigo 
			-- INCLUI PERÍODOS NOTURNOS DE OCORRÊNCIAS
			exec dbo.incluirTempoNoturnoOcorrencias @funcicodigo, @mes, @ano
			declare acordos cursor for 
			select coalesce(acordcodigo,0) from tbgabcartaodeponto (nolock) 
			where funcicodigo = @funcicodigo and cartadatajornada between @periodoiniciodatabase and @periodofimdatabase group by acordcodigo
			open acordos
			fetch next from acordos 
			into @acordcodigo
			while @@FETCH_STATUS=0
			begin
				exec dbo.spug_insereTotalizadoresSemanais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
				exec dbo.spug_insereTotalizadoresMensais @acordcodigo,@funcicodigo,@periodoiniciodatabase,@periodofimdatabase
				--exec dbo.spug_limparCartoesTotalizadores @funcicodigo, @mes, @ano, @acordcodigo 
			fetch next from acordos 
			into @acordcodigo
			end -- END CURSOR acordos
			close acordos
			deallocate acordos
			if @bancodehoras = 1 begin exec spug_incluirSaldoBhCartaodePonto @funcicodigo,@mes,@ano end	
		end
	end

	--select top 1 sem_mov_or_cc_bloq,escala_vinculada,func_ativo,periodoinicio,periodofim from @cartaodeponto
	declare @obs varchar(max) = '';
	declare @haserror bit = 0;

	if (select top 1 sem_mov_or_cc_bloq from @cartaodeponto) = 1
	begin 
		set @obs += 'Sem movimentação ou centro de custo bloqueado;';set @haserror = 1;
	end

	if (select top 1 escala_vinculada from @cartaodeponto) = 0
	begin 
		set @obs += 'Sem escala vinculada;';set @haserror = 1;
	end

	if (select top 1 func_ativo from @cartaodeponto) = 0
	begin 
		set @obs += 'Funcionário inativo;';set @haserror = 1;
	end

	if @haserror = 0 
	begin
		update tbgabitemprocessamento set itproobservacao = @obs,itprosituacao = 3 where itprocodigo = @itprocodigo
	end
	else
	begin 
		update tbgabitemprocessamento set itproobservacao = @obs,itprosituacao = 4 where itprocodigo = @itprocodigo
	end
	-- CORRIGE POSSÍVEIS ANOMALIAS DE O MESMO APONTAMENTO CONTER EM DOIS REGISTROS DIFERENTES NO CARTÃO 13/02/2020
	update tbgabcartaodeponto set carta_realizado_e1 = null, afdtgcodigo_e1 = null 
	where ctococodigo <> 1 and afdtgcodigo_e1 in 
	(select afdtgcodigo_e1 from tbgabcartaodeponto (nolock) 
	where funcicodigo = @funcicodigo and cartamesbase = @mes and cartaanobase = @ano and afdtgcodigo_e1 is not null group by afdtgcodigo_e1 having count(afdtgcodigo_e1) > 1)
	
END
GO
